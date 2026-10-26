import Foundation

/// Which clef a staff uses.
public enum Clef: String, Codable, Sendable {
    case treble, bass

    /// Letter-step position (see `SpelledPitch.diatonicIndex`) of the staff's bottom line:
    /// E4 for treble, G2 for bass.
    public var bottomLineIndex: Int {
        switch self {
        case .treble: return 4 * 7 + 2
        case .bass: return 2 * 7 + 4
        }
    }

    /// Steps above the bottom line (0 = bottom line, 1 = first space, 8 = top line).
    public func staffStep(of pitch: SpelledPitch) -> Int {
        pitch.diatonicIndex - bottomLineIndex
    }
}

/// Written note values, longest first.
public enum NoteType: String, Codable, Sendable, CaseIterable {
    case whole, half, quarter, eighth, sixteenth = "16th"

    /// Length in sixteenths, undotted.
    public var sixteenths: Int {
        switch self {
        case .whole: return 16
        case .half: return 8
        case .quarter: return 4
        case .eighth: return 2
        case .sixteenth: return 1
        }
    }

    /// Filled noteheads (quarter and shorter), versus open ones.
    public var isFilled: Bool { sixteenths <= 4 }
    /// Whether the note has a stem.
    public var hasStem: Bool { self != .whole }
    /// Flags on an unbeamed stem.
    public var flags: Int {
        switch self {
        case .eighth: return 1
        case .sixteenth: return 2
        default: return 0
        }
    }
}

/// One beam level on a note: where the note sits in its beamed group.
public enum Beam: String, Codable, Sendable {
    case begin, `continue`, end
    case forwardHook = "forward hook"
    case backwardHook = "backward hook"
}

/// One written note inside a chord.
public struct ScoreNote: Codable, Equatable, Sendable {
    public var midi: Int
    public var spelled: SpelledPitch
    /// The accidental to print, if any (+1 ♯, −1 ♭, 0 ♮). nil means nothing is printed.
    public var accidental: Int?
    /// Tied to the next note of the same pitch.
    public var tieStart: Bool
    /// Continues a tie from the previous note.
    public var tieStop: Bool

    public init(midi: Int, spelled: SpelledPitch, accidental: Int? = nil, tieStart: Bool = false, tieStop: Bool = false) {
        self.midi = midi
        self.spelled = spelled
        self.accidental = accidental
        self.tieStart = tieStart
        self.tieStop = tieStop
    }
}

/// A chord or rest on one staff.
public struct ScoreEvent: Codable, Equatable, Sendable {
    /// Staff index: 0 = top (treble) staff, 1 = bottom (bass) staff.
    public var staff: Int
    /// Start within the measure, in sixteenths.
    public var start: Int
    /// Length in sixteenths.
    public var duration: Int
    public var type: NoteType
    public var dots: Int
    /// Notes, lowest first. Empty for a rest.
    public var notes: [ScoreNote]
    /// A rest that fills the whole measure (drawn as a centred whole rest whatever the metre).
    public var isMeasureRest: Bool
    /// Beams by level: [0] is the eighth beam, [1] the sixteenth beam. Empty when unbeamed.
    public var beams: [Beam]

    public init(staff: Int, start: Int, duration: Int, type: NoteType, dots: Int, notes: [ScoreNote],
                isMeasureRest: Bool = false, beams: [Beam] = []) {
        self.staff = staff
        self.start = start
        self.duration = duration
        self.type = type
        self.dots = dots
        self.notes = notes
        self.isMeasureRest = isMeasureRest
        self.beams = beams
    }

    public var isRest: Bool { notes.isEmpty }
}

public struct ScoreMeasure: Codable, Equatable, Sendable {
    /// From 1.
    public var number: Int
    /// Start of the measure from the start of the piece, in sixteenths.
    public var startSixteenth: Int
    /// Length in sixteenths.
    public var length: Int
    /// Sorted by staff, then start.
    public var events: [ScoreEvent]

    public init(number: Int, startSixteenth: Int, length: Int, events: [ScoreEvent]) {
        self.number = number
        self.startSixteenth = startSixteenth
        self.length = length
        self.events = events
    }

    public func events(onStaff staff: Int) -> [ScoreEvent] { events.filter { $0.staff == staff } }
}

/// A piano score transcribed from MIDI: one part on one or two staves.
public struct Score: Codable, Equatable, Sendable {
    public var title: String
    public var tempoBPM: Double
    public var timeSignature: TimeSignature
    public var key: KeySignature
    /// Clef of each staff, top to bottom.
    public var staves: [Clef]
    public var measures: [ScoreMeasure]

    public init(title: String, tempoBPM: Double, timeSignature: TimeSignature, key: KeySignature, staves: [Clef], measures: [ScoreMeasure]) {
        self.title = title
        self.tempoBPM = tempoBPM
        self.timeSignature = timeSignature
        self.key = key
        self.staves = staves
        self.measures = measures
    }

    /// The grid the score is written on: sixteenth notes.
    public static let sixteenthsPerQuarter = 4

    /// Measure containing a position given in quarter notes from the start, or nil past the end.
    public func measureIndex(atQuarter quarter: Double) -> Int? {
        let sixteenth = Int((quarter * Double(Self.sixteenthsPerQuarter)).rounded())
        return measures.firstIndex { sixteenth >= $0.startSixteenth && sixteenth < $0.startSixteenth + $0.length }
    }

    /// Staff a pitch would be written on, for marking played notes:
    /// with two staves, middle C and above go on the top staff.
    public func staff(forPitch midi: Int) -> Int {
        staves.count > 1 ? (midi >= 60 ? 0 : 1) : 0
    }
}
