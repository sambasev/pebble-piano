import Foundation

/// The grader's output. Later phases (the app's keyboard colours, audio labelling,
/// the tutor's explanations) all consume this same structure.
public struct GradeReport: Codable, Sendable {
    public var passed: Bool
    public var rubricLevel: String
    public var levels: [LevelResult]
    public var notes: NoteSummary
    public var timing: TimingSummary?
    /// Everything worth telling the student, in score order.
    public var flags: [GradeFlag]
    /// One entry per expected or played note, in score order. Drives per-note colouring.
    public var results: [NoteResult]
}

public struct LevelResult: Codable, Sendable {
    public var check: Rubric.Check
    /// nil when the rubric does not grade this level (the metric is still reported).
    public var passed: Bool?
    public var value: Double?
    public var threshold: Double?
    public var detail: String
}

public struct NoteSummary: Codable, Sendable {
    public var expected: Int
    public var correct: Int
    public var wrongPitch: Int
    public var missed: Int
    public var extra: Int
    /// Notes played before the first or after the last matched note (warm-up noodling); not penalised.
    public var ignoredLeading: Int
    public var ignoredTrailing: Int
    /// correct ÷ expected
    public var accuracy: Double
    /// accuracy minus the extra-note penalty, floored at 0. This is what the rubric checks.
    public var score: Double
}

public struct TimingSummary: Codable, Sendable {
    /// Matched chord events used for the fit.
    public var anchors: Int
    public var fittedBPM: Double
    public var targetBPM: Double
    /// (fitted − target) ÷ target
    public var tempoDeviation: Double
    /// Mean |actual − expected| ÷ expected over consecutive matched events.
    public var meanIOIError: Double
    public var maxIOIError: Double
    /// Coefficient of variation of local tempo.
    public var steadinessCV: Double
}

public struct NoteResult: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case correct, wrongPitch, missed, extra }
    public var kind: Kind
    public var expectedPitch: Int?
    public var playedPitch: Int?
    /// Where in the score; for extra notes, the position of the nearest preceding reference event.
    public var position: ScorePosition
    /// Onset in the take, seconds (nil for missed notes).
    public var playedAt: Double?
}

public struct GradeFlag: Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case wrongPitch, missed, extra, early, late }
    public var kind: Kind
    public var position: ScorePosition
    public var message: String
}
