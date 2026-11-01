import Foundation
import PianoGraderCore

/// How well one phrase (or any run of bars) went in a graded run, from the grader's per-note
/// results: the practice that follows is sized to it, so a couple of slips get a quick polish,
/// not the beginner's note-by-note sequence.
public enum PhraseGrade: Codable, Equatable, Sendable {
    /// No wrong, missed or extra notes, and at most one note early or late.
    case clean
    /// One or two slips with 90% or more of the notes right: polish those bars.
    case minor(bars: [Int])
    /// Every note right, but the timing wandered (two or more early or late notes).
    case timing
    /// 70–90% of the notes right: note by note on the bars with wrong notes, then in time.
    case moderate(bars: [Int])
    /// Under 70% right: the full sequence.
    case major

    public static func grade(_ bars: ClosedRange<Int>, in report: GradeReport) -> PhraseGrade {
        let results = report.results.filter { bars.contains($0.position.measure) }
        let errors = results.filter { $0.kind != .correct }
        let errorBars = Array(Set(errors.map(\.position.measure))).sorted()
        let timingFlags = report.flags.filter { bars.contains($0.position.measure) && ($0.kind == .early || $0.kind == .late) }.count
        let accuracy = Self.accuracy(bars, in: report)
        if errors.isEmpty { return timingFlags <= 1 ? .clean : .timing }
        if errors.count <= 2 && accuracy >= 0.9 { return .minor(bars: errorBars) }
        if accuracy >= 0.7 { return .moderate(bars: errorBars) }
        return .major
    }

    /// The share of the notes in these bars played right (1 when there are none).
    public static func accuracy(_ bars: ClosedRange<Int>, in report: GradeReport) -> Double {
        let results = report.results.filter { bars.contains($0.position.measure) }
        let expected = results.filter { $0.kind != .extra }.count
        let correct = results.filter { $0.kind == .correct }.count
        let extra = results.filter { $0.kind == .extra }.count
        guard expected > 0 else { return extra == 0 ? 1 : 0 }
        return Double(correct) / Double(expected + extra)
    }

    /// Bars with wrong notes, for the grades that have them.
    public var bars: [Int] {
        switch self {
        case .minor(let b), .moderate(let b): return b
        default: return []
        }
    }

    /// "played cleanly", "a slip in bar 6", "the timing wandered"…
    public var summary: String {
        func barList(_ b: [Int]) -> String {
            b.count == 1 ? "bar \(b[0])" : "bars " + b.map(String.init).joined(separator: ", ")
        }
        switch self {
        case .clean: return "played cleanly"
        case .minor(let b): return b.isEmpty ? "a slip or two" : "a slip in \(barList(b))"
        case .timing: return "right notes, but the timing wandered"
        case .moderate(let b): return "some wrong notes in \(barList(b))"
        case .major: return "needs learning from the start"
        }
    }
}
