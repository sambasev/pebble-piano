import Foundation
import PianoGraderCore

// What a learner's saved takes of one piece say over time: whether the notes are improving,
// which bars keep going wrong and how, and how full-speed runs compare with slowed or
// note-by-note ones. The tutor reads this instead of guessing from the latest take alone;
// it never decides a pass (the grader does).

public struct TrendTake: Sendable {
    public var date: Date
    public var report: GradeReport
    /// Printed bar numbers of the excerpt, when the take was a drill; its report's measures are
    /// local to the excerpt (1 = the first of these). Nil for a whole-piece take.
    public var printedMeasures: [Int]?
    public var tempoPercent: Double?
    /// Note by note (wait mode): no evidence about playing in time.
    public var noteByNote: Bool

    public init(date: Date, report: GradeReport, printedMeasures: [Int]? = nil,
                tempoPercent: Double? = nil, noteByNote: Bool = false) {
        self.date = date; self.report = report; self.printedMeasures = printedMeasures
        self.tempoPercent = tempoPercent; self.noteByNote = noteByNote
    }

    /// A run that can show the piece is ready: in time, at full speed.
    public var isFullSpeed: Bool { !noteByNote && (tempoPercent ?? 100) >= 100 }

    func printed(_ measure: Int) -> Int {
        guard let printedMeasures, printedMeasures.indices.contains(measure - 1) else { return measure }
        return printedMeasures[measure - 1]
    }
}

public struct MistakeTrends: Equatable, Sendable {
    public struct TroubleBar: Equatable, Sendable {
        public var bar: Int
        /// Takes (covering this bar) with a wrong, missed or extra note in it.
        public var takesWithErrors: Int
        public var takesCovering: Int
        /// The most frequent slip there: "E4 played as D4", "G4 missed".
        public var usualSlip: String?
    }

    /// Takes looked at, newest last.
    public static let takeLimit = 12
    public static let barLimit = 5

    public var takes: Int
    public var first: Date?
    public var latest: Date?
    public var firstScore: Double?
    public var latestScore: Double?
    public var bestScore: Double?
    /// Latest three takes' mean note score minus the three before them; nil with fewer than 4 takes.
    public var recentChange: Double?
    public var fullSpeedTakes: Int
    public var bestFullSpeedScore: Double?
    public var latestFullSpeedPassed: Bool?
    /// Fitted and target BPM of the latest timed take.
    public var latestFittedBPM: Double?
    public var latestTargetBPM: Double?
    public var troubleBars: [TroubleBar]

    public init(_ all: [TrendTake]) {
        let takes = Array(all.sorted { $0.date < $1.date }.suffix(Self.takeLimit))
        self.takes = takes.count
        first = takes.first?.date
        latest = takes.last?.date
        let scores = takes.map(\.report.notes.score)
        firstScore = scores.first
        latestScore = scores.last
        bestScore = scores.max()
        if scores.count >= 4 {
            let recent = scores.suffix(3), before = scores.dropLast(3).suffix(3)
            recentChange = recent.reduce(0, +) / Double(recent.count) - before.reduce(0, +) / Double(before.count)
        }
        let full = takes.filter(\.isFullSpeed)
        fullSpeedTakes = full.count
        bestFullSpeedScore = full.map(\.report.notes.score).max()
        latestFullSpeedPassed = full.last?.report.passed
        if let timing = takes.last(where: { !$0.noteByNote && $0.report.timing != nil })?.report.timing {
            latestFittedBPM = timing.fittedBPM
            latestTargetBPM = timing.targetBPM
        }

        var covering: [Int: Int] = [:], erring: [Int: Int] = [:], slips: [Int: [String: Int]] = [:]
        for take in takes {
            let bars = Set(take.report.results.map { take.printed($0.position.measure) })
            for bar in bars { covering[bar, default: 0] += 1 }
            var wrongHere = Set<Int>()
            for result in take.report.results where result.kind != .correct {
                let bar = take.printed(result.position.measure)
                wrongHere.insert(bar)
                slips[bar, default: [:]][Self.slip(result), default: 0] += 1
            }
            for bar in wrongHere { erring[bar, default: 0] += 1 }
        }
        troubleBars = erring.filter { $0.value >= 2 }
            .map { bar, count in
                TroubleBar(bar: bar, takesWithErrors: count, takesCovering: covering[bar] ?? count,
                           usualSlip: slips[bar]?.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key)
            }
            .sorted { $0.takesWithErrors != $1.takesWithErrors ? $0.takesWithErrors > $1.takesWithErrors : $0.bar < $1.bar }
            .prefix(Self.barLimit).map { $0 }
    }

    static func slip(_ result: NoteResult) -> String {
        let expected = result.expectedPitch.map(PitchName.of), played = result.playedPitch.map(PitchName.of)
        switch result.kind {
        case .wrongPitch: return "\(expected ?? "?") played as \(played ?? "?")"
        case .missed: return "\(expected ?? "a note") missed"
        case .extra: return "extra \(played ?? "note")"
        case .correct: return "correct"
        }
    }

    /// The trend as context lines, for the piece named `title`.
    public func summary(title: String) -> String {
        guard takes > 0 else { return "No saved takes of \(title) yet." }
        func pct(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))%" } ?? "none" }
        var lines = ["\(title): \(takes) graded take\(takes == 1 ? "" : "s") looked at. Note score first \(pct(firstScore)), latest \(pct(latestScore)), best \(pct(bestScore))."]
        if let recentChange {
            let points = Int((recentChange * 100).rounded())
            lines.append("Last 3 takes vs the 3 before: \(points > 0 ? "+" : "")\(points) points (\(abs(points) < 3 ? "flat" : points > 0 ? "improving" : "slipping")).")
        }
        lines.append(fullSpeedTakes == 0
            ? "No full-speed, in-time takes yet: slowed or note-by-note runs are not evidence the piece is ready."
            : "Full speed, in time: \(fullSpeedTakes) take\(fullSpeedTakes == 1 ? "" : "s"), best \(pct(bestFullSpeedScore)), latest passed: \(latestFullSpeedPassed == true ? "yes" : "no").")
        if let fitted = latestFittedBPM, let target = latestTargetBPM {
            lines.append(String(format: "Latest timed take: %.0f BPM against a target of %.0f.", fitted, target))
        }
        if troubleBars.isEmpty {
            lines.append("No bar went wrong in more than one take.")
        } else {
            lines.append("Bars that keep going wrong (printed numbers): " + troubleBars.map { b in
                "bar \(b.bar), \(b.takesWithErrors) of \(b.takesCovering) takes" + (b.usualSlip.map { ", usually \($0)" } ?? "")
            }.joined(separator: "; ") + ".")
        }
        return lines.joined(separator: "\n")
    }
}
