import Foundation

/// Combines a model's reading of a system with the measured noteheads, bar by bar and staff by
/// staff. Where the number of heads found equals the number of notes the model read, each note
/// keeps the model's rhythm and takes the measured pitch; anywhere else the bar keeps the
/// model's reading and is flagged for the learner to check.
///
/// When the reading and the page disagree on how many bars there are (the model skipped a bar,
/// or split one), the bars are lined up by their note counts first, so the bars that do match
/// are still checked, a bar the reading skipped appears as an empty flagged bar ("Fix this bar"
/// reads it), and a bar that isn't on the page is flagged.
public enum BarMerge {
    public enum Status: Equatable, Sendable {
        /// Every measured pitch agreed with the model.
        case confirmed
        /// Measured pitch replaced the model's for this many notes.
        case corrected(Int)
        /// Not checked; the learner should look at this bar.
        case flagged(Reason)

        public var isTrusted: Bool {
            if case .flagged = self { return false }
            return true
        }
    }

    public enum Reason: Equatable, Sendable {
        /// The model read a bar that couldn't be matched to one on the page.
        case notOnPage
        /// A bar on the page that the reading skipped.
        case skippedByReading
        /// A different number of noteheads was found than the model read.
        case noteCountDiffers(found: Int, read: Int)
        /// Some heads sit between a line and a space, and disagree with the model.
        case unclearHeads(Int)

        /// For the review screen.
        public var message: String {
            switch self {
            case .notOnPage: return "This bar couldn't be matched to the page. Please check it."
            case .skippedByReading: return "The reading skipped this bar. Tap Fix this bar to read it."
            case let .noteCountDiffers(found, read):
                return found < read ? "A note here couldn't be measured. Please check it."
                                    : "Something here looks like an extra note. Please check it."
            case .unclearHeads: return "A note here sits between a line and a space. Please check it."
            }
        }
    }

    /// One merged note: the model's note, with its position replaced when measured.
    public struct Note: Equatable, Sendable {
        public var note: SystemReading.Note
        public var clef: SystemReading.Clef
        /// The measured head this note was matched to, if any.
        public var head: NoteheadGeometry.Head?

        public init(note: SystemReading.Note, clef: SystemReading.Clef, head: NoteheadGeometry.Head? = nil) {
            self.note = note
            self.clef = clef
            self.head = head
        }

        public var name: String {
            note.rest ? "r" : StaffPitch.name(clef: clef, position: note.position)
        }
    }

    public struct Bar: Equatable, Sendable {
        public var upper: [Note]
        public var lower: [Note]
        public var upperStatus: Status
        public var lowerStatus: Status
        /// Which bar on the page (index into the system's bars) this is, if it was matched.
        public var pageBar: Int?

        public init(upper: [Note], lower: [Note], upperStatus: Status, lowerStatus: Status, pageBar: Int?) {
            self.upper = upper
            self.lower = lower
            self.upperStatus = upperStatus
            self.lowerStatus = lowerStatus
            self.pageBar = pageBar
        }

        public func notes(_ staff: SystemReading.StaffName) -> [Note] { staff == .upper ? upper : lower }
        public func status(_ staff: SystemReading.StaffName) -> Status { staff == .upper ? upperStatus : lowerStatus }
        public var isTrusted: Bool { upperStatus.isTrusted && lowerStatus.isTrusted }
    }

    public static func merge(_ reading: SystemReading, _ system: NoteheadGeometry.System) -> [Bar] {
        let pairs = align(reading, system)
        return pairs.map { pair -> Bar in
            switch pair {
            case let .both(i, j): return mergeBar(reading.measures[i], system, pageBar: j)
            case let .readingOnly(i):
                let m = reading.measures[i]
                return Bar(upper: readNotes(m.upper), lower: readNotes(m.lower), upperStatus: .flagged(.notOnPage),
                           lowerStatus: .flagged(.notOnPage), pageBar: nil)
            case let .pageOnly(j):
                return Bar(upper: [], lower: [], upperStatus: .flagged(.skippedByReading),
                           lowerStatus: .flagged(.skippedByReading), pageBar: j)
            }
        }
    }

    static func readNotes(_ staff: SystemReading.Staff) -> [Note] {
        staff.notes.map { Note(note: $0, clef: staff.clef) }
    }

    static func mergeBar(_ m: SystemReading.Measure, _ system: NoteheadGeometry.System, pageBar j: Int) -> Bar {
        var bar = Bar(upper: [], lower: [], upperStatus: .confirmed, lowerStatus: .confirmed, pageBar: j)
        for staffName in SystemReading.StaffName.allCases {
            var notes = readNotes(staffName == .upper ? m.upper : m.lower)
            let sounding = notes.indices.filter { !notes[$0].note.rest }
            let heads = headsIn(system, staffName, bar: j)
            let status: Status
            if heads.count != sounding.count {
                status = .flagged(.noteCountDiffers(found: heads.count, read: sounding.count))
            } else {
                var changed = 0, unclear = 0
                for (k, head) in zip(sounding, heads) {
                    notes[k].head = head
                    guard notes[k].note.position != head.position else { continue }
                    if head.isClear {
                        notes[k].note.position = head.position
                        changed += 1
                    } else {
                        unclear += 1  // between a line and a space: don't trust it
                    }
                }
                status = unclear > 0 ? .flagged(.unclearHeads(unclear)) : changed > 0 ? .corrected(changed) : .confirmed
            }
            if staffName == .upper { bar.upper = notes; bar.upperStatus = status } else { bar.lower = notes; bar.lowerStatus = status }
        }
        return bar
    }

    static func headsIn(_ system: NoteheadGeometry.System, _ staff: SystemReading.StaffName, bar j: Int) -> [NoteheadGeometry.Head] {
        let lo = system.barEdges[j], hi = system.barEdges[j + 1]
        return system.heads(staff).filter { $0.x > lo && $0.x < hi }
    }

    // MARK: Lining up bars

    enum Pair: Equatable { case both(Int, Int), readingOnly(Int), pageOnly(Int) }

    /// Lines up the reading's bars with the page's: one to one when the counts agree;
    /// otherwise by edit distance over each bar's (upper, lower) note counts.
    static func align(_ reading: SystemReading, _ system: NoteheadGeometry.System) -> [Pair] {
        let n = reading.measures.count, m = system.barCount
        if n == m { return (0..<n).map { .both($0, $0) } }
        let read = reading.measures.map { ms in
            (ms.upper.notes.filter { !$0.rest }.count, ms.lower.notes.filter { !$0.rest }.count)
        }
        let page = (0..<m).map { (headsIn(system, .upper, bar: $0).count, headsIn(system, .lower, bar: $0).count) }
        func cost(_ a: (Int, Int), _ b: (Int, Int)) -> Double {
            (a.0 == b.0 ? 0 : 1) + (a.1 == b.1 ? 0 : 1)
        }
        let gap = 1.5
        var d = [[Double]](repeating: [Double](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { d[i][0] = Double(i) * gap }
        for j in 0...m { d[0][j] = Double(j) * gap }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    d[i][j] = min(d[i - 1][j - 1] + cost(read[i - 1], page[j - 1]), d[i - 1][j] + gap, d[i][j - 1] + gap)
                }
            }
        }
        var out: [Pair] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, d[i][j] == d[i - 1][j - 1] + cost(read[i - 1], page[j - 1]) {
                out.append(.both(i - 1, j - 1)); i -= 1; j -= 1
            } else if i > 0, d[i][j] == d[i - 1][j] + gap {
                out.append(.readingOnly(i - 1)); i -= 1
            } else {
                out.append(.pageOnly(j - 1)); j -= 1
            }
        }
        return out.reversed()
    }
}
