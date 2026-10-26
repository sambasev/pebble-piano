import Foundation
import Yams

/// Grading thresholds for one book and level.
///
/// A rubric is a YAML file, or a Markdown file whose YAML front matter holds the
/// thresholds and whose body is guidance for the tutor (kept in `guidance`).
/// Every key is optional; missing keys fall back to the beginner defaults.
public struct Rubric: Codable, Equatable, Sendable {
    public enum Check: String, Codable, Sendable, CaseIterable {
        case notes, rhythm, tempo
    }

    public struct Notes: Codable, Equatable, Sendable {
        /// Minimum share of expected notes played correctly (0–1).
        public var minAccuracy: Double = 0.95
        /// Each extra note subtracts this many "notes" from the score.
        public var extraNotePenalty: Double = 0.5

        enum CodingKeys: String, CodingKey {
            case minAccuracy = "min_accuracy"
            case extraNotePenalty = "extra_note_penalty"
        }

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            minAccuracy = try c.decodeIfPresent(Double.self, forKey: .minAccuracy) ?? 0.95
            extraNotePenalty = try c.decodeIfPresent(Double.self, forKey: .extraNotePenalty) ?? 0.5
        }
    }

    public struct Rhythm: Codable, Equatable, Sendable {
        /// Maximum mean inter-onset-interval error, as a share of the notated duration.
        public var maxMeanIOIError: Double = 0.25
        /// Individual intervals off by more than this are flagged.
        public var flagIOIError: Double = 0.40

        enum CodingKeys: String, CodingKey {
            case maxMeanIOIError = "max_mean_ioi_error"
            case flagIOIError = "flag_ioi_error"
        }

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            maxMeanIOIError = try c.decodeIfPresent(Double.self, forKey: .maxMeanIOIError) ?? 0.25
            flagIOIError = try c.decodeIfPresent(Double.self, forKey: .flagIOIError) ?? 0.40
        }
    }

    public struct Tempo: Codable, Equatable, Sendable {
        /// Allowed deviation of the fitted tempo from the target, as a share (0.10 = ±10%).
        public var tolerance: Double = 0.15
        /// Maximum coefficient of variation of local tempo (0 = metronomic).
        public var maxSteadinessCV: Double = 0.20

        enum CodingKeys: String, CodingKey {
            case tolerance
            case maxSteadinessCV = "max_steadiness_cv"
        }

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tolerance = try c.decodeIfPresent(Double.self, forKey: .tolerance) ?? 0.15
            maxSteadinessCV = try c.decodeIfPresent(Double.self, forKey: .maxSteadinessCV) ?? 0.20
        }
    }

    /// Play-along mode: how much slack the player gets before the music stops and rewinds.
    public struct PlayAlong: Codable, Equatable, Sendable {
        /// A chord may be struck this early.
        public var earlyMs: Double = 250
        /// …or this late, and still count.
        public var lateMs: Double = 400
        /// Extra lateness allowed for the microphone (detection takes time).
        public var micExtraLateMs: Double = 120
        /// Extra lateness allowed for the computer keyboard: musical typing or clicking the
        /// on-screen keys, which are slower and less even than a piano key.
        public var keysExtraLateMs: Double = 150
        /// A bar fails when more than this share of its chords is missed…
        public var maxMissFraction: Double = 0.34
        /// …capped at this many misses.
        public var maxMissesPerBar: Int = 2
        /// This many chords missed in a row always rewinds (the player stopped).
        public var maxConsecutiveMisses: Int = 3
        /// Share of a chord's notes that must be struck for it to count.
        public var minChordCoverage: Double = 0.5

        enum CodingKeys: String, CodingKey {
            case earlyMs = "early_ms"
            case lateMs = "late_ms"
            case micExtraLateMs = "mic_extra_late_ms"
            case keysExtraLateMs = "keys_extra_late_ms"
            case maxMissFraction = "max_miss_fraction"
            case maxMissesPerBar = "max_misses_per_bar"
            case maxConsecutiveMisses = "max_consecutive_misses"
            case minChordCoverage = "min_chord_coverage"
        }

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = PlayAlong()
            earlyMs = try c.decodeIfPresent(Double.self, forKey: .earlyMs) ?? d.earlyMs
            lateMs = try c.decodeIfPresent(Double.self, forKey: .lateMs) ?? d.lateMs
            micExtraLateMs = try c.decodeIfPresent(Double.self, forKey: .micExtraLateMs) ?? d.micExtraLateMs
            keysExtraLateMs = try c.decodeIfPresent(Double.self, forKey: .keysExtraLateMs) ?? d.keysExtraLateMs
            maxMissFraction = try c.decodeIfPresent(Double.self, forKey: .maxMissFraction) ?? d.maxMissFraction
            maxMissesPerBar = try c.decodeIfPresent(Int.self, forKey: .maxMissesPerBar) ?? d.maxMissesPerBar
            maxConsecutiveMisses = try c.decodeIfPresent(Int.self, forKey: .maxConsecutiveMisses) ?? d.maxConsecutiveMisses
            minChordCoverage = try c.decodeIfPresent(Double.self, forKey: .minChordCoverage) ?? d.minChordCoverage
        }

        /// Never stops the music: every miss is allowed (misses are still counted).
        public static var keepGoing: PlayAlong {
            var p = PlayAlong()
            p.earlyMs = 300; p.lateMs = 500
            p.maxMissFraction = 1; p.maxMissesPerBar = 10_000; p.maxConsecutiveMisses = 10_000
            p.minChordCoverage = 0.5
            return p
        }

        /// Wide windows; a bar replays only when about half of it is missed.
        public static var gentle: PlayAlong {
            var p = PlayAlong()
            p.earlyMs = 300; p.lateMs = 500
            p.maxMissFraction = 0.5; p.maxMissesPerBar = 3; p.maxConsecutiveMisses = 4
            p.minChordCoverage = 0.5
            return p
        }

        /// The beginner defaults.
        public static var standard: PlayAlong { PlayAlong() }

        /// Tight windows; any missed chord replays the bar, and every note of a chord counts.
        public static var strict: PlayAlong {
            var p = PlayAlong()
            p.earlyMs = 120; p.lateMs = 200; p.micExtraLateMs = 80; p.keysExtraLateMs = 100
            p.maxMissFraction = 0; p.maxMissesPerBar = 0; p.maxConsecutiveMisses = 1
            p.minChordCoverage = 1
            return p
        }

        /// Extra lateness for notes from `input`, in milliseconds.
        public func extraLateMs(for input: InputSource) -> Double {
            switch input {
            case .midi: return 0
            case .microphone: return micExtraLateMs
            case .computerKeyboard: return keysExtraLateMs
            }
        }

        /// The judge's settings, with the microphone's extra slack when listening through it.
        public func judgeSettings(microphone: Bool) -> PlayAlongJudge.Settings {
            judgeSettings(input: microphone ? .microphone : .midi)
        }

        /// The judge's settings for notes arriving from `input`.
        public func judgeSettings(input: InputSource) -> PlayAlongJudge.Settings {
            var s = PlayAlongJudge.Settings()
            s.earlySeconds = earlyMs / 1000
            s.lateSeconds = (lateMs + extraLateMs(for: input)) / 1000
            s.maxMissFraction = maxMissFraction
            s.maxMissesPerBar = maxMissesPerBar
            s.maxConsecutiveMisses = maxConsecutiveMisses
            s.minChordCoverage = minChordCoverage
            return s
        }
    }

    public var level: String = "beginner"
    public var checks: [Check] = [.notes, .rhythm]
    /// Notes starting within this many milliseconds count as one chord.
    public var chordWindowMs: Double = 50
    /// Overrides the reference file's tempo as the target.
    public var targetBPM: Double? = nil
    public var notes = Notes()
    public var rhythm = Rhythm()
    public var tempo = Tempo()
    public var playAlong = PlayAlong()
    /// Consecutive passes the app should require before advancing (not used by the CLI).
    public var consecutivePasses: Int = 2
    /// Markdown body after the front matter: guidance the tutor reads when explaining results.
    public var guidance: String? = nil

    enum CodingKeys: String, CodingKey {
        case level, checks, notes, rhythm, tempo, guidance
        case playAlong = "play_along"
        case chordWindowMs = "chord_window_ms"
        case targetBPM = "target_bpm"
        case consecutivePasses = "consecutive_passes"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decodeIfPresent(String.self, forKey: .level) ?? "beginner"
        checks = try c.decodeIfPresent([Check].self, forKey: .checks) ?? [.notes, .rhythm]
        chordWindowMs = try c.decodeIfPresent(Double.self, forKey: .chordWindowMs) ?? 50
        targetBPM = try c.decodeIfPresent(Double.self, forKey: .targetBPM)
        notes = try c.decodeIfPresent(Notes.self, forKey: .notes) ?? Notes()
        rhythm = try c.decodeIfPresent(Rhythm.self, forKey: .rhythm) ?? Rhythm()
        tempo = try c.decodeIfPresent(Tempo.self, forKey: .tempo) ?? Tempo()
        playAlong = try c.decodeIfPresent(PlayAlong.self, forKey: .playAlong) ?? PlayAlong()
        consecutivePasses = try c.decodeIfPresent(Int.self, forKey: .consecutivePasses) ?? 2
        guidance = try c.decodeIfPresent(String.self, forKey: .guidance)
    }

    public static let beginner = Rubric()

    public func grades(_ check: Check) -> Bool { checks.contains(check) }

    // MARK: Loading

    public static func load(url: URL) throws -> Rubric {
        try parse(String(contentsOf: url, encoding: .utf8))
    }

    /// Parses YAML, or Markdown with YAML front matter between `---` lines.
    public static func parse(_ text: String) throws -> Rubric {
        let (yaml, body) = splitFrontMatter(text)
        var rubric = Rubric()
        if !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rubric = try YAMLDecoder().decode(Rubric.self, from: yaml)
        }
        if let body, !body.isEmpty { rubric.guidance = body }
        return rubric
    }

    /// Returns (yaml, markdownBody). Text without front matter is treated as plain YAML.
    static func splitFrontMatter(_ text: String) -> (String, String?) {
        let lines = text.components(separatedBy: .newlines)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return (text, nil)
        }
        guard let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return (lines.dropFirst().joined(separator: "\n"), nil)
        }
        let yaml = lines[1..<close].joined(separator: "\n")
        let body = lines[(close + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (yaml, body)
    }
}
