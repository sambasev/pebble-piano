import Foundation

/// What a model reads from one system (an upper and a lower staff joined by a brace): bars,
/// and for each staff its clef and notes. Notes carry their *staff position* (counted in lines
/// and spaces from the bottom line), not a pitch: pitch is worked out from the clef in code, so
/// the model can't get octaves wrong. See `scripts/ai_probe2.py`, which this mirrors.
public struct SystemReading: Codable, Equatable, Sendable {
    public var measureCount: Int
    public var measures: [Measure]

    public init(measureCount: Int, measures: [Measure]) {
        self.measureCount = measureCount
        self.measures = measures
    }

    /// The same reading with every bar's staves in the given clefs: the learner said which clefs
    /// the music is in, so they win over what was read (positions don't change, pitches do).
    public func withClefs(upper: Clef, lower: Clef) -> SystemReading {
        var r = self
        for i in r.measures.indices {
            r.measures[i].upper.clef = upper
            r.measures[i].lower.clef = lower
        }
        return r
    }

    public struct Measure: Codable, Equatable, Sendable {
        public var upper: Staff
        public var lower: Staff

        public init(upper: Staff, lower: Staff) {
            self.upper = upper
            self.lower = lower
        }

        public subscript(staff: StaffName) -> Staff {
            get { staff == .upper ? upper : lower }
            set { if staff == .upper { upper = newValue } else { lower = newValue } }
        }
    }

    public struct Staff: Codable, Equatable, Sendable {
        public var clef: Clef
        public var notes: [Note]

        public init(clef: Clef, notes: [Note]) {
            self.clef = clef
            self.notes = notes
        }
    }

    public struct Note: Codable, Equatable, Sendable {
        public var rest: Bool
        /// 0 = bottom line, 1 = the space above it … 8 = top line; −2 = first ledger line below.
        public var position: Int
        public var duration: Duration
        public var dotted: Bool
        public var accidental: Accidental
        /// A printed fingering number (1–5), if any.
        public var finger: Int?

        public init(rest: Bool = false, position: Int, duration: Duration, dotted: Bool = false,
                    accidental: Accidental = .none, finger: Int? = nil) {
            self.rest = rest
            self.position = position
            self.duration = duration
            self.dotted = dotted
            self.accidental = accidental
            self.finger = finger
        }

        /// Length in quarter notes.
        public var quarters: Double { duration.quarters * (dotted ? 1.5 : 1) }

        /// "quarter", "half." … the same spelling as the answer key.
        public var durationName: String { duration.rawValue + (dotted ? "." : "") }
    }

    public enum StaffName: String, CaseIterable, Codable, Sendable { case upper, lower }

    public enum Clef: String, Codable, Sendable { case treble, bass }

    public enum Duration: String, Codable, Sendable {
        case whole, half, quarter, eighth, sixteenth

        public var quarters: Double {
            switch self {
            case .whole: return 4
            case .half: return 2
            case .quarter: return 1
            case .eighth: return 0.5
            case .sixteenth: return 0.25
            }
        }
    }

    public enum Accidental: String, Codable, Sendable { case none, sharp, flat, natural }
}

/// Pitch from a clef and a staff position.
public enum StaffPitch {
    static let letters = ["C", "D", "E", "F", "G", "A", "B"]
    static let semitones = [0, 2, 4, 5, 7, 9, 11]

    /// The bottom line as a diatonic step count from C0: treble E4, bass G2.
    static func bottomLine(_ clef: SystemReading.Clef) -> Int {
        clef == .treble ? 4 * 7 + 2 : 2 * 7 + 4
    }

    static func step(_ clef: SystemReading.Clef, _ position: Int) -> Int { bottomLine(clef) + position }

    /// "C4", "G5" … (no accidental).
    public static func name(clef: SystemReading.Clef, position: Int) -> String {
        let s = step(clef, position)
        let octave = Int(floor(Double(s) / 7))
        return letters[s - octave * 7] + String(octave)
    }

    /// MIDI note number, with the accidental applied. Only this note's own accidental: in a bar,
    /// use `BarAccidentals` (or `BarMerge.Bar.midiPitches`) so earlier ones carry.
    public static func midi(clef: SystemReading.Clef, position: Int,
                            accidental: SystemReading.Accidental = .none) -> Int {
        let shift = accidental == .sharp ? 1 : accidental == .flat ? -1 : 0
        return midi(step: step(clef, position), alter: shift)
    }

    /// MIDI note number of a diatonic step from C0, raised or lowered by `alter` semitones.
    static func midi(step s: Int, alter: Int) -> Int {
        let octave = Int(floor(Double(s) / 7))
        return (octave + 1) * 12 + semitones[s - octave * 7] + alter
    }
}

/// The accidentals in force in one bar of one staff, read left to right: a sharp, flat or natural
/// lasts for the rest of the bar on its own line or space (that octave only), as printed music
/// does. Key signatures aren't read yet, so everything else is C major.
public struct BarAccidentals: Sendable {
    /// Diatonic step from C0 → semitones up (+1) or down (−1); 0 once a natural cancels it.
    private var inForce: [Int: Int] = [:]

    public init() {}

    /// The alteration in force on this step before the next note there.
    public func alter(atStep step: Int) -> Int { inForce[step] ?? 0 }

    /// A note on `step` with its printed `accidental`: remembers that accidental for the rest of
    /// the bar and returns the note's alteration (−1, 0 or +1).
    public mutating func play(step: Int, accidental: SystemReading.Accidental) -> Int {
        switch accidental {
        case .sharp: inForce[step] = 1
        case .flat: inForce[step] = -1
        case .natural: inForce[step] = 0
        case .none: break
        }
        return alter(atStep: step)
    }
}
