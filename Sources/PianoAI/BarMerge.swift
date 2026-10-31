import Foundation

/// Combines a model's reading of a system with the measured noteheads, bar by bar and staff by
/// staff. Where the number of heads found equals the number of notes the model read, each note
/// keeps the model's rhythm and takes the measured pitch; anywhere else the bar keeps the
/// model's reading and is flagged for the learner to check.
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
        /// The image and the reading disagree on how many bars the system has.
        case barCountDiffers(found: Int, read: Int)
        /// A different number of noteheads was found than the model read.
        case noteCountDiffers(found: Int, read: Int)
        /// Some heads sit between a line and a space, and disagree with the model.
        case unclearHeads(Int)

        /// For the review screen.
        public var message: String {
            switch self {
            case .barCountDiffers: return "This line's bars couldn't be matched to the page. Please check it."
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

        public var name: String {
            note.rest ? "r" : StaffPitch.name(clef: clef, position: note.position)
        }
    }

    public struct Bar: Equatable, Sendable {
        public var upper: [Note]
        public var lower: [Note]
        public var upperStatus: Status
        public var lowerStatus: Status

        public func notes(_ staff: SystemReading.StaffName) -> [Note] { staff == .upper ? upper : lower }
        public func status(_ staff: SystemReading.StaffName) -> Status { staff == .upper ? upperStatus : lowerStatus }
    }

    public static func merge(_ reading: SystemReading, _ system: NoteheadGeometry.System) -> [Bar] {
        let sameBars = system.barCount == reading.measures.count
        return reading.measures.enumerated().map { pair -> Bar in
            let (i, m) = pair
            var bar = Bar(upper: [], lower: [], upperStatus: .confirmed, lowerStatus: .confirmed)
            for staffName in SystemReading.StaffName.allCases {
                let staff = staffName == .upper ? m.upper : m.lower
                var notes = staff.notes.map { Note(note: $0, clef: staff.clef, head: nil) }
                let sounding = notes.indices.filter { !notes[$0].note.rest }
                let status: Status
                if !sameBars {
                    status = .flagged(.barCountDiffers(found: system.barCount, read: reading.measures.count))
                } else {
                    let lo = system.barEdges[i], hi = system.barEdges[i + 1]
                    let heads = system.heads(staffName).filter { $0.x > lo && $0.x < hi }
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
                }
                if staffName == .upper { bar.upper = notes; bar.upperStatus = status } else { bar.lower = notes; bar.lowerStatus = status }
            }
            return bar
        }
    }
}
