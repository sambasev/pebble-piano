import Foundation
import PianoGraderCore

/// Technical exercises made in code: scales, arpeggios, broken chords and five-finger
/// patterns in any key, with standard fingering. Deterministic and pure, so a generated
/// exercise is graded like any other piece and the tutor model never writes graded notes.
///
/// Every exercise is in 4/4, one note per beat (the last note held to the end of its bar),
/// at `baseBPM`, within the on-screen keyboard (`range`, C2–C6). Hands together plays the
/// left hand an octave below the right, on a second track, so either hand can be practised.
public enum ExerciseGenerator {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case majorScale, naturalMinorScale, harmonicMinorScale, arpeggio, brokenChord, fiveFinger

        /// "harmonic minor scale", "arpeggio".
        public var name: String {
            switch self {
            case .majorScale: return "major scale"
            case .naturalMinorScale: return "natural minor scale"
            case .harmonicMinorScale: return "harmonic minor scale"
            default: return label
            }
        }

        var label: String {
            switch self {
            case .majorScale, .naturalMinorScale, .harmonicMinorScale: return "scale"
            case .arpeggio: return "arpeggio"
            case .brokenChord: return "broken chords"
            case .fiveFinger: return "five-finger pattern"
            }
        }
    }

    public enum Failure: Error, Equatable, Sendable {
        case unknownKey, octaves, outOfRange
    }

    /// The on-screen keyboard, C2–C6.
    public static let range: ClosedRange<Int> = 36...84
    public static let baseBPM = 80.0

    /// A key as written: "G", "F#", "Bb minor", "c# min", "Am".
    public struct Key: Equatable, Sendable {
        /// Pitch class of the tonic, 0 = C.
        public var tonic: Int
        /// "F#", "Bb": the spelling, for titles and the key signature.
        public var name: String
        /// Said minor ("minor", "min" or "m"). Scale kinds decide for themselves.
        public var isMinor: Bool

        private static let letters: [Character: (pc: Int, fifths: Int)] = [
            "C": (0, 0), "D": (2, 2), "E": (4, 4), "F": (5, -1), "G": (7, 1), "A": (9, 3), "B": (11, 5),
        ]

        public init?(_ text: String) {
            var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard let first = rest.first, let letter = Self.letters[Character(first.uppercased())] else { return nil }
            rest = rest.dropFirst()
            var shift = 0
            var accidentals = ""
            while let c = rest.first, "#b♯♭".contains(c) {
                let sharp = c == "#" || c == "♯"
                shift += sharp ? 1 : -1
                accidentals += sharp ? "#" : "b"
                rest = rest.dropFirst()
            }
            guard abs(shift) <= 1 else { return nil }
            let quality = rest.trimmingCharacters(in: .whitespaces).lowercased()
            switch quality {
            case "", "major", "maj": isMinor = false
            case "minor", "min", "m": isMinor = true
            default: return nil
            }
            tonic = ((letter.pc + shift) % 12 + 12) % 12
            name = String(first).uppercased() + accidentals
            majorFifths = letter.fifths + 7 * shift
        }

        private var majorFifths: Int

        /// The key signature for this tonic, major or minor.
        public func signature(minor: Bool) -> KeySignature {
            var fifths = majorFifths - (minor ? 3 : 0)
            if fifths > 7 { fifths -= 12 }
            if fifths < -7 { fifths += 12 }
            return KeySignature(fifths: fifths, isMinor: minor)
        }
    }

    public struct Request: Equatable, Sendable {
        public var kind: Kind
        public var key: Key
        /// 1 or 2. A five-finger pattern is always one position.
        public var octaves: Int
        public var hand: Hand

        public init(kind: Kind, key: Key, octaves: Int = 1, hand: Hand = .right) {
            self.kind = kind; self.key = key; self.octaves = octaves; self.hand = hand
        }

        /// Whether the music is minor: scale kinds say so, chord kinds follow the key.
        public var isMinor: Bool {
            switch kind {
            case .majorScale: return false
            case .naturalMinorScale, .harmonicMinorScale: return true
            case .arpeggio, .brokenChord, .fiveFinger: return key.isMinor
            }
        }
    }

    public struct Exercise: Sendable {
        public var request: Request
        public var title: String
        /// Track 0 is the right hand, track 1 the left (when both play); one hand is track 0.
        public var sequence: MIDISequence
        /// One per note, in time order then hand (right first).
        public var fingering: [FingeredNote]
    }

    public static func generate(_ request: Request) throws -> Exercise {
        guard (1...2).contains(request.octaves) else { throw Failure.octaves }
        let line = pattern(request)
        let span = line.map(\.offset).max() ?? 0
        let pc = request.key.tonic
        // The right hand from the tonic above Middle C, the left an octave lower; both move
        // down an octave when the top would leave the keyboard.
        func fits(_ root: Int) -> Bool { range.contains(root) && root + span <= range.upperBound }
        let parts: [(hand: Hand, root: Int, track: Int)]
        switch request.hand {
        case .right:
            guard let root = [60 + pc, 48 + pc, 36 + pc].first(where: fits) else { throw Failure.outOfRange }
            parts = [(.right, root, 0)]
        case .left:
            guard let root = [48 + pc, 36 + pc].first(where: fits) else { throw Failure.outOfRange }
            parts = [(.left, root, 0)]
        case .both:
            guard let root = [60 + pc, 48 + pc].first(where: { fits($0) && fits($0 - 12) }) else { throw Failure.outOfRange }
            parts = [(.right, root, 0), (.left, root - 12, 1)]
        }

        let secondsPerBeat = 60 / baseBPM
        let lastBeat = Double(line.count - 1)
        let end = (lastBeat / 4).rounded(.down) * 4 + 4
        var notes: [NoteEvent] = []
        var fingering: [FingeredNote] = []
        for (index, step) in line.enumerated() {
            let beat = Double(index)
            let length = index == line.count - 1 ? end - beat : 1
            for part in parts {
                let pitch = part.root + step.offset
                guard range.contains(pitch) else { throw Failure.outOfRange }
                notes.append(NoteEvent(pitch: pitch, onset: beat * secondsPerBeat, offset: (beat + length * 0.95) * secondsPerBeat,
                                       onsetBeats: beat, offsetBeats: beat + length * 0.95, track: part.track))
                fingering.append(FingeredNote(pitch: pitch, quarter: beat, durationQuarters: length, hand: part.hand,
                                              finger: part.hand == .left ? step.left : step.right,
                                              measureNumber: Int(beat / 4) + 1))
            }
        }
        let title = Self.title(request)
        let sequence = MIDISequence(notes: notes, initialTempoBPM: baseBPM, timeSignature: .common,
                                    keySignature: request.key.signature(minor: request.isMinor), title: title)
        return Exercise(request: request, title: title, sequence: sequence, fingering: fingering)
    }

    public static func title(_ r: Request) -> String {
        let quality: String
        switch r.kind {
        case .majorScale: quality = "major"
        case .naturalMinorScale: quality = "natural minor"
        case .harmonicMinorScale: quality = "harmonic minor"
        default: quality = r.isMinor ? "minor" : "major"
        }
        let hands = r.hand == .right ? "right hand" : r.hand == .left ? "left hand" : "hands together"
        let octaves = r.kind == .fiveFinger ? "" : r.octaves == 1 ? ", 1 octave" : ", \(r.octaves) octaves"
        return "\(r.key.name) \(quality) \(r.kind.label)\(octaves), \(hands)"
    }

    // MARK: Notes and fingers

    /// One note of the line: semitones above the tonic, and each hand's finger.
    struct Step: Equatable { var offset: Int; var right: Int; var left: Int }

    static func pattern(_ r: Request) -> [Step] {
        switch r.kind {
        case .majorScale, .naturalMinorScale, .harmonicMinorScale: return scale(r)
        case .arpeggio: return arpeggio(r)
        case .brokenChord: return brokenChords(r)
        case .fiveFinger: return fiveFinger(r)
        }
    }

    static let major = [0, 2, 4, 5, 7, 9, 11]
    static let naturalMinor = [0, 2, 3, 5, 7, 8, 10]
    static let harmonicMinor = [0, 2, 3, 5, 7, 8, 11]

    /// Up and back down, `octaves` octaves.
    static func scale(_ r: Request) -> [Step] {
        let degrees = r.kind == .majorScale ? major : r.kind == .naturalMinorScale ? naturalMinor : harmonicMinor
        let table = r.isMinor ? minorScaleFingers : majorScaleFingers
        let fingers = table[r.key.tonic]!
        var up: [Step] = []
        for octave in 0..<r.octaves {
            for (d, interval) in degrees.enumerated() {
                // The tonic inside a run: the right hand's first finger; the left hand's top-note finger.
                let right = fingers.right[d]
                let left = d == 0 && octave > 0 ? fingers.left[7] : fingers.left[d]
                up.append(Step(offset: 12 * octave + interval, right: right, left: left))
            }
        }
        up.append(Step(offset: 12 * r.octaves, right: fingers.right[7], left: fingers.left[7]))
        return up + up.dropLast().reversed()
    }

    /// One octave of a scale's fingering, tonic to tonic, ascending. Natural and harmonic minor share it.
    typealias ScaleFingers = (right: [Int], left: [Int])

    static let majorScaleFingers: [Int: ScaleFingers] = {
        let white = [1, 2, 3, 1, 2, 3, 4, 5], whiteLeft = [5, 4, 3, 2, 1, 3, 2, 1]
        let flatLeft = [3, 2, 1, 4, 3, 2, 1, 3]
        return [
            0: (white, whiteLeft),                            // C
            7: (white, whiteLeft),                            // G
            2: (white, whiteLeft),                            // D
            9: (white, whiteLeft),                            // A
            4: (white, whiteLeft),                            // E
            11: (white, [4, 3, 2, 1, 4, 3, 2, 1]),            // B
            6: ([2, 3, 4, 1, 2, 3, 1, 2], [4, 3, 2, 1, 3, 2, 1, 4]), // F#/Gb
            1: ([2, 3, 1, 2, 3, 4, 1, 2], flatLeft),          // Db
            8: ([3, 4, 1, 2, 3, 1, 2, 3], flatLeft),          // Ab
            3: ([3, 1, 2, 3, 4, 1, 2, 3], flatLeft),          // Eb
            10: ([4, 1, 2, 3, 1, 2, 3, 4], flatLeft),         // Bb
            5: ([1, 2, 3, 4, 1, 2, 3, 4], whiteLeft),         // F
        ]
    }()

    static let minorScaleFingers: [Int: ScaleFingers] = {
        let white = [1, 2, 3, 1, 2, 3, 4, 5], whiteLeft = [5, 4, 3, 2, 1, 3, 2, 1]
        return [
            9: (white, whiteLeft),                            // A
            4: (white, whiteLeft),                            // E
            11: (white, [4, 3, 2, 1, 4, 3, 2, 1]),            // B
            6: ([3, 4, 1, 2, 3, 1, 2, 3], [4, 3, 2, 1, 3, 2, 1, 4]), // F#
            1: ([3, 4, 1, 2, 3, 1, 2, 3], [3, 2, 1, 4, 3, 2, 1, 3]), // C#
            8: ([3, 4, 1, 2, 3, 1, 2, 3], [3, 2, 1, 3, 2, 1, 4, 3]), // G#
            3: ([3, 1, 2, 3, 4, 1, 2, 3], [2, 1, 4, 3, 2, 1, 3, 2]), // D#/Eb
            10: ([4, 1, 2, 3, 1, 2, 3, 4], [2, 1, 3, 2, 1, 4, 3, 2]), // Bb
            5: ([1, 2, 3, 4, 1, 2, 3, 4], whiteLeft),         // F
            0: (white, whiteLeft),                            // C
            7: (white, whiteLeft),                            // G
            2: (white, whiteLeft),                            // D
        ]
    }()

    /// A root-position arpeggio's fingers: the first root, third and fifth; the root inside a
    /// run; the third and fifth after it; the top note.
    struct ArpeggioFingers { var first: [Int]; var middle: Int; var inner: [Int]; var top: Int }

    static func arpeggioFingers(tonic: Int, minor: Bool) -> (right: ArpeggioFingers, left: ArpeggioFingers) {
        let right = ArpeggioFingers(first: [1, 2, 3], middle: 1, inner: [2, 3], top: 5)
        let left = ArpeggioFingers(first: [5, 4, 2], middle: 1, inner: [4, 2], top: 1)
        guard !minor else { return (right, left) }
        // Db, Eb, Ab and Bb major keep the thumb off the black-key root.
        let blackRight = ArpeggioFingers(first: [2, 1, 2], middle: 4, inner: [1, 2], top: 4)
        switch tonic {
        case 1, 3, 8: return (blackRight, ArpeggioFingers(first: [2, 1, 4], middle: 2, inner: [1, 4], top: 2))
        case 10: return (blackRight, ArpeggioFingers(first: [3, 2, 1], middle: 3, inner: [2, 1], top: 3))
        default: return (right, left)
        }
    }

    static func triad(minor: Bool) -> [Int] { minor ? [0, 3, 7] : [0, 4, 7] }

    /// Up and back down through the triad's notes, `octaves` octaves.
    static func arpeggio(_ r: Request) -> [Step] {
        let chord = triad(minor: r.isMinor)
        let fingers = arpeggioFingers(tonic: r.key.tonic, minor: r.isMinor)
        var up: [Step] = []
        for octave in 0..<r.octaves {
            for (i, interval) in chord.enumerated() {
                func finger(_ f: ArpeggioFingers) -> Int { octave == 0 ? f.first[i] : i == 0 ? f.middle : f.inner[i - 1] }
                up.append(Step(offset: 12 * octave + interval, right: finger(fingers.right), left: finger(fingers.left)))
            }
        }
        up.append(Step(offset: 12 * r.octaves, right: fingers.right.top, left: fingers.left.top))
        return up + up.dropLast().reversed()
    }

    /// Root position, first and second inversion, each low–middle–high–middle, climbing
    /// `octaves` octaves and ending on the root.
    static func brokenChords(_ r: Request) -> [Step] {
        let chord = triad(minor: r.isMinor)
        let positions = [chord, [chord[1], chord[2], 12], [chord[2], 12, 12 + chord[1]]]
        let right = [[1, 3, 5], [1, 2, 5], [1, 3, 5]]
        let left = [[5, 3, 1], [5, 3, 1], [5, 2, 1]]
        var steps: [Step] = []
        for octave in 0..<r.octaves {
            for (p, notes) in positions.enumerated() {
                for i in [0, 1, 2, 1] {
                    steps.append(Step(offset: 12 * octave + notes[i], right: right[p][i], left: left[p][i]))
                }
            }
        }
        steps.append(Step(offset: 12 * r.octaves, right: 1, left: 5))
        return steps
    }

    /// The first five notes of the key, up and down, one finger per note.
    static func fiveFinger(_ r: Request) -> [Step] {
        let degrees = Array((r.isMinor ? naturalMinor : major).prefix(5))
        let up = degrees.enumerated().map { i, interval in Step(offset: interval, right: i + 1, left: 5 - i) }
        return up + up.dropLast().reversed()
    }
}
