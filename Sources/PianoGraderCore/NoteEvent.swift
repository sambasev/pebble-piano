import Foundation

/// One note as played or written: pitch plus when it starts and stops.
public struct NoteEvent: Codable, Equatable, Sendable {
    /// MIDI note number (60 = middle C).
    public var pitch: Int
    /// Start time in seconds from the start of the file or take.
    public var onset: Double
    /// End time in seconds.
    public var offset: Double
    /// MIDI velocity 1–127. Recorded but not graded in milestone 0.
    public var velocity: Int
    /// Start position in quarter notes from the start (from the file's ticks).
    /// Only meaningful for reference files; for live takes it is derived from seconds.
    public var onsetBeats: Double
    /// End position in quarter notes, from the file's ticks. nil for live takes.
    public var offsetBeats: Double?
    public var channel: Int
    /// Index of the file's track the note came from (0 for takes and format-0 files).
    public var track: Int

    public init(pitch: Int, onset: Double, offset: Double, velocity: Int = 80, onsetBeats: Double = 0,
                offsetBeats: Double? = nil, channel: Int = 0, track: Int = 0) {
        self.pitch = pitch
        self.onset = onset
        self.offset = offset
        self.velocity = velocity
        self.onsetBeats = onsetBeats
        self.offsetBeats = offsetBeats
        self.channel = channel
        self.track = track
    }

    private enum CodingKeys: String, CodingKey {
        case pitch, onset, offset, velocity, onsetBeats, offsetBeats, channel, track
    }

    /// Older encodings have no `offsetBeats` or `track`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pitch = try c.decode(Int.self, forKey: .pitch)
        onset = try c.decode(Double.self, forKey: .onset)
        offset = try c.decode(Double.self, forKey: .offset)
        velocity = try c.decodeIfPresent(Int.self, forKey: .velocity) ?? 80
        onsetBeats = try c.decodeIfPresent(Double.self, forKey: .onsetBeats) ?? 0
        offsetBeats = try c.decodeIfPresent(Double.self, forKey: .offsetBeats)
        channel = try c.decodeIfPresent(Int.self, forKey: .channel) ?? 0
        track = try c.decodeIfPresent(Int.self, forKey: .track) ?? 0
    }
}

/// A key signature: the number of sharps (positive) or flats (negative), and the mode.
public struct KeySignature: Codable, Equatable, Sendable {
    public var fifths: Int
    public var isMinor: Bool

    public init(fifths: Int, isMinor: Bool = false) {
        self.fifths = max(-7, min(7, fifths))
        self.isMinor = isMinor
    }

    public static let cMajor = KeySignature(fifths: 0)
}

public struct TimeSignature: Codable, Equatable, Sendable {
    public var numerator: Int
    public var denominator: Int

    public init(numerator: Int, denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
    }

    public static let common = TimeSignature(numerator: 4, denominator: 4)

    /// Quarter notes per measure (4/4 → 4, 3/4 → 3, 6/8 → 3).
    public var quartersPerMeasure: Double { Double(numerator) * 4.0 / Double(denominator) }
    /// Length of one beat (the denominator note) in quarter notes.
    public var quartersPerBeat: Double { 4.0 / Double(denominator) }
}

/// A position in the score, 1-based: measure 3, beat 2.5.
public struct ScorePosition: Codable, Equatable, Sendable {
    public var measure: Int
    public var beat: Double

    public init(measure: Int, beat: Double) {
        self.measure = measure
        self.beat = beat
    }

    public init(quarters: Double, timeSignature ts: TimeSignature) {
        let qpm = ts.quartersPerMeasure
        let m = Int((quarters / qpm + 1e-6).rounded(.down))
        let within = max(0, quarters - Double(m) * qpm)
        self.measure = m + 1
        self.beat = ((within / ts.quartersPerBeat + 1) * 100).rounded() / 100
    }

    /// "m3 b2" or "m3 b2.5"
    public var label: String {
        let b = beat == beat.rounded() ? String(Int(beat)) : String(format: "%g", beat)
        return "m\(measure) b\(b)"
    }
}

/// A parsed MIDI file (or recorded take).
public struct MIDISequence: Sendable {
    /// Sorted by onset, then pitch.
    public var notes: [NoteEvent]
    public var ticksPerQuarter: Int
    /// Tempo in effect at the start of the file. 120 if the file has none.
    public var initialTempoBPM: Double
    /// First time signature in the file. 4/4 if the file has none.
    public var timeSignature: TimeSignature
    /// First key signature in the file, if it has one.
    public var keySignature: KeySignature?
    /// The first track's name, if the file gives one.
    public var title: String?

    public init(notes: [NoteEvent], ticksPerQuarter: Int = 480, initialTempoBPM: Double = 120,
                timeSignature: TimeSignature = .common, keySignature: KeySignature? = nil, title: String? = nil) {
        self.notes = notes.sorted { ($0.onset, $0.pitch) < ($1.onset, $1.pitch) }
        self.ticksPerQuarter = ticksPerQuarter
        self.initialTempoBPM = initialTempoBPM
        self.timeSignature = timeSignature
        self.keySignature = keySignature
        self.title = title
    }
}

public enum PitchName {
    private static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// 60 → "C4", 61 → "C#4"
    public static func of(_ pitch: Int) -> String {
        let octave = pitch / 12 - 1
        return names[((pitch % 12) + 12) % 12] + String(octave)
    }
}

extension MIDISequence {
    /// The same music at one steady tempo: every note keeps its place in beats, and its
    /// times in seconds are worked out again at `bpm`. Used when a backing track sets the tempo.
    public func retimed(bpm: Double) -> MIDISequence {
        let bpm = max(1, bpm)
        let oldSecondsPerQuarter = 60 / max(1, initialTempoBPM)
        let newSecondsPerQuarter = 60 / bpm
        let notes = self.notes.map { n -> NoteEvent in
            var m = n
            let offBeats = n.offsetBeats ?? (n.onsetBeats + (n.offset - n.onset) / oldSecondsPerQuarter)
            m.onset = n.onsetBeats * newSecondsPerQuarter
            m.offset = max(m.onset, offBeats * newSecondsPerQuarter)
            m.offsetBeats = offBeats
            return m
        }
        return MIDISequence(notes: notes, ticksPerQuarter: ticksPerQuarter, initialTempoBPM: bpm,
                            timeSignature: timeSignature, keySignature: keySignature, title: title)
    }
}

extension MIDISequence {
    /// Measures in the music (1-based count): up to the last note's measure.
    public var measureCount: Int {
        let qpm = timeSignature.quartersPerMeasure
        guard let last = notes.map(\.onsetBeats).max(), qpm > 0 else { return 0 }
        return Int((last / qpm + 1e-6).rounded(.down)) + 1
    }

    /// Just measures `range` (1-based, as `ScorePosition` counts them), moved to the start.
    /// Notes keep their place in the bar; a note held past the last measure is cut at its end.
    /// Assumes one steady tempo (`initialTempoBPM`), as lesson files have. Used to drill a bar.
    public func measures(_ range: ClosedRange<Int>) -> MIDISequence {
        let qpm = timeSignature.quartersPerMeasure
        let start = Double(max(1, range.lowerBound) - 1) * qpm
        let end = Double(max(1, range.upperBound)) * qpm
        let secondsPerQuarter = 60 / max(1, initialTempoBPM)
        let kept = notes
            .filter { $0.onsetBeats >= start - 1e-6 && $0.onsetBeats < end - 1e-6 }
            .map { n -> NoteEvent in
                var m = n
                let off = n.offsetBeats ?? (n.onsetBeats + (n.offset - n.onset) / secondsPerQuarter)
                m.onsetBeats = n.onsetBeats - start
                m.offsetBeats = max(m.onsetBeats, min(off, end) - start)
                m.onset = m.onsetBeats * secondsPerQuarter
                m.offset = m.offsetBeats! * secondsPerQuarter
                return m
            }
        return MIDISequence(notes: kept, ticksPerQuarter: ticksPerQuarter, initialTempoBPM: initialTempoBPM,
                            timeSignature: timeSignature, keySignature: keySignature, title: title)
    }
}
