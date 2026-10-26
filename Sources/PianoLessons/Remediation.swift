import Foundation
import PianoGraderCore

// Fix my mistakes: after failed Perform runs, find the worst bar and drill it in fixed steps
// (the grading design's set of actions), then go back to Perform. Pure logic; the lesson
// runner plays the steps.

/// One step of a bar drill.
public struct DrillStep: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// The bar in wait mode: the music waits for each note.
        case notes
        /// The bar looped with the clicks, slowed down.
        case slow
        /// The bar looped at full speed.
        case fullSpeed
        /// The bar with the bars either side, at full speed.
        case context
    }

    public var kind: Kind
    /// Measures to play, 1-based.
    public var measures: ClosedRange<Int>
    /// Play-along speed, percent (wait mode ignores it).
    public var tempoPercent: Double

    public var isWaitMode: Bool { kind == .notes }

    public var title: String {
        switch kind {
        case .notes: return "Get the notes"
        case .slow: return "Slowly, in time"
        case .fullSpeed: return "Full speed"
        case .context: return "With the bars around it"
        }
    }

    public init(kind: Kind, measures: ClosedRange<Int>, tempoPercent: Double = 100) {
        self.kind = kind
        self.measures = measures
        self.tempoPercent = tempoPercent
    }
}

/// A drill on one bar: its steps, and how far the learner has got.
public struct BarDrill: Equatable, Sendable {
    public let measure: Int
    public let steps: [DrillStep]
    public let cleanRunsNeeded: Int
    public let maxRunsPerStep: Int?

    public private(set) var stepIndex = 0
    /// Runs of the current step.
    public private(set) var runs = 0
    /// Clean runs in a row on the current step.
    public private(set) var cleanStreak = 0

    public enum Outcome: Equatable, Sendable {
        /// Play the step again.
        case again(clean: Bool)
        /// The step is done (`movedOn`: by running out of runs or asking), here's the next.
        case nextStep(DrillStep, movedOn: Bool)
        /// Every step is done: perform the song again.
        case finished(movedOn: Bool)
    }

    public init(measure: Int, steps: [DrillStep], cleanRunsNeeded: Int = 1, maxRunsPerStep: Int? = nil) {
        self.measure = measure
        self.steps = steps
        self.cleanRunsNeeded = max(1, cleanRunsNeeded)
        self.maxRunsPerStep = maxRunsPerStep.map { max(1, $0) }
    }

    public var step: DrillStep? { steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }
    public var isFinished: Bool { stepIndex >= steps.count }

    /// Clean runs the current step needs (wait mode always finishes every note, so once).
    public var needed: Int { step?.isWaitMode == true ? 1 : cleanRunsNeeded }

    /// A run of the current step finished.
    public mutating func record(clean: Bool) -> Outcome {
        guard !isFinished else { return .finished(movedOn: false) }
        runs += 1
        cleanStreak = clean ? cleanStreak + 1 : 0
        if cleanStreak >= needed { return advance(movedOn: false) }
        if let maxRunsPerStep, runs >= maxRunsPerStep { return advance(movedOn: true) }
        return .again(clean: clean)
    }

    /// The learner asks to move on: the step ends without passing.
    public mutating func moveOn() -> Outcome {
        guard !isFinished else { return .finished(movedOn: true) }
        return advance(movedOn: true)
    }

    private mutating func advance(movedOn: Bool) -> Outcome {
        stepIndex += 1
        runs = 0
        cleanStreak = 0
        if let next = step { return .nextStep(next, movedOn: movedOn) }
        return .finished(movedOn: movedOn)
    }
}

public enum RemediationPlanner {
    /// The bar most worth fixing across `reports` (most recent failed runs): wrong and missed
    /// notes count 2, extra notes and early or late ones 1, and each replay of the bar
    /// (`replays`, 1-based measure → count) 2. Ties go to the earlier bar. nil: nothing to fix.
    public static func worstMeasure(in reports: [GradeReport], replays: [Int: Int] = [:]) -> Int? {
        var weight: [Int: Int] = [:]
        for report in reports {
            for flag in report.flags {
                let w: Int
                switch flag.kind {
                case .wrongPitch, .missed: w = 2
                case .extra, .early, .late: w = 1
                }
                weight[flag.position.measure, default: 0] += w
            }
        }
        for (measure, count) in replays where count > 0 { weight[measure, default: 0] += 2 * count }
        return weight.filter { $0.value > 0 }.max { a, b in
            a.value != b.value ? a.value < b.value : a.key > b.key
        }?.key
    }

    /// The steps for bar `measure` of a song with `measureCount` bars: notes in wait mode,
    /// slowly in time, full speed, then with a bar either side (left out when the song is
    /// one bar long).
    public static func drill(measure: Int, measureCount: Int, persona: Persona) -> BarDrill {
        let count = max(1, measureCount)
        let m = min(max(1, measure), count)
        var steps = [
            DrillStep(kind: .notes, measures: m...m),
            DrillStep(kind: .slow, measures: m...m, tempoPercent: persona.drill.slowTempoPercent),
            DrillStep(kind: .fullSpeed, measures: m...m),
        ]
        let context = max(1, m - 1)...min(count, m + 1)
        if context != m...m { steps.append(DrillStep(kind: .context, measures: context)) }
        return BarDrill(measure: m, steps: steps, cleanRunsNeeded: persona.drill.cleanRunsNeeded,
                        maxRunsPerStep: persona.drill.maxRunsPerStep)
    }

    /// Whether a drill run counts as clean: it passed, nothing was replayed, and at least
    /// 90% of the notes were right.
    public static func isClean(_ report: GradeReport, replays: Int) -> Bool {
        report.passed && replays == 0 && report.notes.accuracy >= 0.9
    }
}

/// Says what went wrong in a graded run, from its note results, in plain words:
/// "You played D instead of E in bar 2, twice. E is finger 3."
public enum MistakeExplainer {
    /// Up to `limit` lines, most frequent first (then by bar). `finger` gives the finger for a
    /// pitch when the hand position is known.
    public static func explain(_ report: GradeReport, limit: Int = 3,
                               finger: (Int) -> Int? = { _ in nil }) -> [String] {
        struct Key: Hashable { var kind: NoteResult.Kind; var measure: Int; var expected: Int?; var played: Int? }
        var counts: [Key: Int] = [:]
        var order: [Key] = []
        for r in report.results {
            let key: Key
            switch r.kind {
            case .wrongPitch:
                key = Key(kind: .wrongPitch, measure: r.position.measure, expected: r.expectedPitch, played: r.playedPitch)
            case .missed:
                key = Key(kind: .missed, measure: r.position.measure, expected: r.expectedPitch, played: nil)
            case .correct, .extra:
                continue
            }
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        var lines: [(count: Int, measure: Int, text: String)] = order.map { key in
            let n = counts[key]!
            let times = n == 1 ? "" : (n == 2 ? ", twice" : ", \(n) times")
            let expected = key.expected.map { NoteName(pitch: $0).letter } ?? "a note"
            let hint = key.expected.flatMap(finger).map { " \(expected) is finger \($0)." } ?? ""
            switch key.kind {
            case .wrongPitch:
                let played = key.played.map { NoteName(pitch: $0).letter } ?? "another note"
                return (n, key.measure, "You played \(played) instead of \(expected) in bar \(key.measure)\(times).\(hint)")
            default:
                return (n, key.measure, "You missed \(expected) in bar \(key.measure)\(times).\(hint)")
            }
        }
        // Timing, for bars with no note mistakes.
        let noteBars = Set(lines.map(\.measure))
        var timing: [Int: (early: Int, late: Int)] = [:]
        for f in report.flags where !noteBars.contains(f.position.measure) {
            switch f.kind {
            case .early: timing[f.position.measure, default: (0, 0)].early += 1
            case .late: timing[f.position.measure, default: (0, 0)].late += 1
            default: break
            }
        }
        for (measure, t) in timing {
            let text = t.early >= t.late ? "Bar \(measure) rushed: wait for the click." : "Bar \(measure) came in late: get ready for the next note sooner."
            lines.append((t.early + t.late, measure, text))
        }
        return lines
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.measure < $1.measure }
            .prefix(limit)
            .map(\.text)
    }

    /// Fingers for the right hand in Middle C position (C 1 … G 5).
    public static func middleCFinger(_ pitch: Int) -> Int? {
        [60: 1, 62: 2, 64: 3, 65: 4, 67: 5][pitch]
    }
}
