import Foundation
import PianoGraderCore

/// What the results screen shows for a graded run: notes, timing and help used.
public struct PerformanceSummary: Equatable, Sendable {
    /// The grader's note score, 0–1 (accuracy less the extra-note penalty).
    public var notes: Double
    /// 0–1; nil when the take had too few notes to measure timing.
    public var timing: Double?
    /// The run used wait mode or a slowed tempo.
    public var helpUsed: Bool

    public init(notes: Double, timing: Double?, helpUsed: Bool) {
        self.notes = notes
        self.timing = timing
        self.helpUsed = helpUsed
    }
}

/// The thresholds for one, two and three stars.
public struct StarRules: Equatable, Sendable {
    public var oneStarNotes = 0.80
    public var twoStarNotes = 0.90
    public var twoStarTiming = 0.60
    public var threeStarNotes = 0.95
    public var threeStarTiming = 0.80

    public init() {}

    public static let standard = StarRules()
}

public enum Stars {
    /// Timing as 0–1 from the grader's mean inter-onset error. The rubric's pass limit
    /// (`max_mean_ioi_error`, 0.25 for beginners) scores 0.5; twice that or worse scores 0;
    /// perfectly even playing scores 1. So for beginners ★★ (0.6) needs a mean error of at
    /// most 0.20 and ★★★ (0.8) at most 0.10.
    public static func timingScore(meanIOIError: Double, rubric: Rubric) -> Double {
        let limit = rubric.rhythm.maxMeanIOIError
        guard limit > 0 else { return meanIOIError <= 0 ? 1 : 0 }
        return min(1, max(0, 1 - meanIOIError / (2 * limit)))
    }

    public static func summary(report: GradeReport, rubric: Rubric, helpUsed: Bool) -> PerformanceSummary {
        PerformanceSummary(notes: min(1, max(0, report.notes.score)),
                           timing: report.timing.map { timingScore(meanIOIError: $0.meanIOIError, rubric: rubric) },
                           helpUsed: helpUsed)
    }

    /// 0–3. When timing couldn't be measured, the timing conditions count as met.
    /// Three stars also needs a run without help.
    public static func compute(_ s: PerformanceSummary, rules: StarRules = .standard) -> Int {
        let timing = s.timing ?? 1
        if s.notes >= rules.threeStarNotes && timing >= rules.threeStarTiming && !s.helpUsed { return 3 }
        if s.notes >= rules.twoStarNotes && timing >= rules.twoStarTiming { return 2 }
        if s.notes >= rules.oneStarNotes { return 1 }
        return 0
    }

    public static func compute(report: GradeReport, rubric: Rubric, helpUsed: Bool,
                               rules: StarRules = .standard) -> Int {
        compute(summary(report: report, rubric: rubric, helpUsed: helpUsed), rules: rules)
    }
}
