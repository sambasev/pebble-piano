import Foundation

/// A take's mistakes sorted into the kinds a teacher would name, for tracking a student over time.
///
/// - pitch: the right moment, the wrong key.
/// - missed: an expected note never played.
/// - extra: a note played that isn't in the score.
/// - timing: a single note noticeably early or late against the take's own pulse.
/// - tempo: the take as a whole rushed, dragged or wandered (at most one per take).
public struct MistakeTally: Codable, Equatable, Sendable {
    public enum Category: String, Codable, Sendable, CaseIterable, Identifiable {
        case pitch, missed, extra, timing, tempo

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .pitch: "Wrong notes"
            case .missed: "Missed notes"
            case .extra: "Extra notes"
            case .timing: "Timing"
            case .tempo: "Tempo"
            }
        }

        /// One line for a teacher: what the category counts.
        public var explanation: String {
            switch self {
            case .pitch: "Played a different key from the one written"
            case .missed: "Skipped a note that was written"
            case .extra: "Added a note that isn't written"
            case .timing: "A note came in early or late"
            case .tempo: "The whole take rushed, dragged or wandered"
            }
        }
    }

    /// Fitted tempo this far from the target (either way) counts as a tempo mistake. The beginner rubric's tolerance.
    public static let tempoTolerance = 0.15
    /// Local-tempo variation above this counts as a tempo mistake (the take wandered). The beginner rubric's limit.
    public static let maxSteadinessCV = 0.20

    public var pitch: Int
    public var missed: Int
    public var extra: Int
    /// Early plus late notes.
    public var timing: Int
    public var early: Int
    public var late: Int
    /// 1 when the take rushed, dragged or wandered, else 0.
    public var tempo: Int
    /// Notes the score asked for: the yardstick for rates.
    public var expected: Int

    public init(pitch: Int = 0, missed: Int = 0, extra: Int = 0, early: Int = 0, late: Int = 0,
                tempo: Int = 0, expected: Int = 0) {
        self.pitch = pitch
        self.missed = missed
        self.extra = extra
        self.early = early
        self.late = late
        self.timing = early + late
        self.tempo = tempo
        self.expected = expected
    }

    public init(_ report: GradeReport) {
        let early = report.flags.filter { $0.kind == .early }.count
        let late = report.flags.filter { $0.kind == .late }.count
        var tempo = 0
        if let t = report.timing, abs(t.tempoDeviation) > Self.tempoTolerance || t.steadinessCV > Self.maxSteadinessCV {
            tempo = 1
        }
        self.init(pitch: report.notes.wrongPitch, missed: report.notes.missed, extra: report.notes.extra,
                  early: early, late: late, tempo: tempo, expected: report.notes.expected)
    }

    public subscript(category: Category) -> Int {
        switch category {
        case .pitch: pitch
        case .missed: missed
        case .extra: extra
        case .timing: timing
        case .tempo: tempo
        }
    }

    /// Note-level mistakes (everything except tempo, which is one verdict per take).
    public var noteMistakes: Int { pitch + missed + extra + timing }

    public static func + (a: MistakeTally, b: MistakeTally) -> MistakeTally {
        MistakeTally(pitch: a.pitch + b.pitch, missed: a.missed + b.missed, extra: a.extra + b.extra,
                     early: a.early + b.early, late: a.late + b.late, tempo: a.tempo + b.tempo,
                     expected: a.expected + b.expected)
    }
}
