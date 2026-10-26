import Foundation

/// A recorded backing track for a passage, annotated by hand so the app can seek by bar.
///
/// ```json
/// "backing": { "file": "../Backing/p29.m4a", "startSeconds": 1.84, "bpm": 92,
///              "timeSignature": "4/4", "key": "C", "countInBars": 1 }
/// ```
public struct BackingAnnotation: Codable, Equatable, Sendable {
    /// Audio file (m4a, mp3, wav, aiff…), relative to the annotations file.
    public var file: String
    /// Where in the audio the reference MIDI's beat 0 falls (bar 1, beat 1 when there is no
    /// pickup). Anything before it is intro, heard only when starting from the first bar.
    public var startSeconds: Double
    /// Tempo of the recording in quarter notes per minute (the same unit as MIDI tempo).
    /// The recording is assumed to keep a steady tempo.
    public var bpm: Double
    public var timeSignature: TimeSignature
    /// Key of the recording, e.g. "C", "F#", "Bb", "Am", "C# minor". Informational for now.
    public var key: String?
    /// Bars of clicks before playing starts. Defaults to 1.
    public var countInBars: Int?
    /// Playback never starts before this time in the file (default: the file's start).
    public var trimStartSeconds: Double?
    /// …and stops at this time (default: the file's end).
    public var trimEndSeconds: Double?

    public init(file: String, startSeconds: Double, bpm: Double, timeSignature: TimeSignature = .common,
                key: String? = nil, countInBars: Int? = nil) {
        self.file = file
        self.startSeconds = startSeconds
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.key = key
        self.countInBars = countInBars
    }

    enum CodingKeys: String, CodingKey {
        case file, startSeconds, bpm, timeSignature, key, countInBars, trimStartSeconds, trimEndSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = try c.decode(String.self, forKey: .file)
        startSeconds = try c.decodeIfPresent(Double.self, forKey: .startSeconds) ?? 0
        bpm = try c.decode(Double.self, forKey: .bpm)
        guard bpm > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .bpm, in: c, debugDescription: "bpm must be positive")
        }
        if let text = try c.decodeIfPresent(String.self, forKey: .timeSignature) {
            guard let ts = TimeSignature(text) else {
                throw DecodingError.dataCorruptedError(forKey: .timeSignature, in: c,
                                                       debugDescription: "expected a time signature like \"3/4\"")
            }
            timeSignature = ts
        } else {
            timeSignature = .common
        }
        key = try c.decodeIfPresent(String.self, forKey: .key)
        countInBars = try c.decodeIfPresent(Int.self, forKey: .countInBars)
        trimStartSeconds = try c.decodeIfPresent(Double.self, forKey: .trimStartSeconds)
        trimEndSeconds = try c.decodeIfPresent(Double.self, forKey: .trimEndSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(file, forKey: .file)
        try c.encode(startSeconds, forKey: .startSeconds)
        try c.encode(bpm, forKey: .bpm)
        try c.encode("\(timeSignature.numerator)/\(timeSignature.denominator)", forKey: .timeSignature)
        try c.encodeIfPresent(key, forKey: .key)
        try c.encodeIfPresent(countInBars, forKey: .countInBars)
        try c.encodeIfPresent(trimStartSeconds, forKey: .trimStartSeconds)
        try c.encodeIfPresent(trimEndSeconds, forKey: .trimEndSeconds)
    }

    /// The key as a key signature, when `key` names one.
    public var keySignature: KeySignature? { key.flatMap(KeySignature.init(name:)) }
}

extension TimeSignature {
    /// Parses "3/4", "6/8".
    public init?(_ text: String) {
        let parts = text.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let n = Int(parts[0]), let d = Int(parts[1]), n > 0,
              [1, 2, 4, 8, 16, 32].contains(d) else { return nil }
        self.init(numerator: n, denominator: d)
    }
}

extension KeySignature {
    private static let majors: [String: Int] = [
        "C": 0, "G": 1, "D": 2, "A": 3, "E": 4, "B": 5, "F#": 6, "C#": 7,
        "F": -1, "Bb": -2, "Eb": -3, "Ab": -4, "Db": -5, "Gb": -6, "Cb": -7,
    ]
    private static let minors: [String: Int] = [
        "A": 0, "E": 1, "B": 2, "F#": 3, "C#": 4, "G#": 5, "D#": 6, "A#": 7,
        "D": -1, "G": -2, "C": -3, "F": -4, "Bb": -5, "Eb": -6, "Ab": -7,
    ]

    /// Parses "C", "Bb", "F# major", "Am", "C# minor". nil if not recognised.
    public init?(name: String) {
        var text = name.trimmingCharacters(in: .whitespaces)
        var minor = false
        for suffix in [" minor", " min", "minor", "min", "m"] where text.lowercased().hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            minor = true
            break
        }
        if !minor {
            for suffix in [" major", " maj", "major", "maj"] where text.lowercased().hasSuffix(suffix) {
                text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        guard let first = text.first else { return nil }
        let tonic = String(first).uppercased() + text.dropFirst().replacingOccurrences(of: "♯", with: "#")
            .replacingOccurrences(of: "♭", with: "b")
        guard let fifths = (minor ? Self.minors : Self.majors)[tonic] else { return nil }
        self.init(fifths: fifths, isMinor: minor)
    }
}
