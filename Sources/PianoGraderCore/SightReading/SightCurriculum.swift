import Foundation

// Reading music, the eye's counterpart to ear training: the staff and its clefs, note names in
// each clef, note values and rests. Each question is a tiny score (drawn by `ScoreRenderer`)
// answered with a button or, for note names, by playing the key itself.

public struct SightStageID: Hashable, Codable, Sendable, Identifiable {
    public let level: Int
    public let stage: Int
    public var id: String { "\(level).\(stage)" }
    public init(level: Int, stage: Int) { self.level = level; self.stage = stage }
    public static let first = SightStageID(level: 1, stage: 1)
}

public struct SightStage: Identifiable, Sendable {
    public let id: SightStageID
    public let title: String
    /// One line for the card and the page heading.
    public let detail: String
    /// What to know before the quiz: the lesson's explain step.
    public let lesson: String
    /// Keys to light while the lesson is read (the notes the stage reads), MIDI.
    public let keys: [Int]

    /// Note-name stages: a question can be answered by playing the key.
    public var answersAtKeys: Bool { id.level == 2 || id.level == 3 || id == SightStageID(level: 1, stage: 3) }
}

public struct SightLevel: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let detail: String
    public let stages: [SightStage]
}

public struct SightAnswer: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

public struct SightQuestion: Identifiable, Sendable {
    public let id: String
    public let stage: SightStageID
    public let prompt: String
    /// What to look at: one staff, one symbol (or none, for the clef questions).
    public let score: Score
    public let correctAnswer: SightAnswer
    public let choices: [SightAnswer]
    /// The key that answers it when played: note-name questions only.
    public let playPitch: Int?
    public let explanation: String
}

public enum SightCurriculum {
    public static let levels: [SightLevel] = [
        SightLevel(id: 1, title: "The staff & clefs", detail: "Where music is written, and how to find Middle C.", stages: [
            SightStage(id: .init(level: 1, stage: 1), title: "Lines and spaces",
                       detail: "A staff has five lines and four spaces.",
                       lesson: "Music is written on a staff: five lines with four spaces between them. A note sits either on a line (the line runs through its middle) or in a space (between two lines). Notes higher on the staff sound higher.",
                       keys: []),
            SightStage(id: .init(level: 1, stage: 2), title: "Two clefs",
                       detail: "The treble clef and the bass clef.",
                       lesson: "A clef at the start of the staff says which notes the lines stand for. The treble clef (G clef) curls around the G line and is for higher notes, usually your right hand. The bass clef (F clef) has two dots around the F line and is for lower notes, usually your left hand.",
                       keys: []),
            SightStage(id: .init(level: 1, stage: 3), title: "Middle C",
                       detail: "Find Middle C in both clefs.",
                       lesson: "Middle C sits between the two staves, on its own short line called a ledger line. In the treble clef it hangs just below the staff; in the bass clef it sits just above. D is the space just above it, and B the space just below. Play the note you see, or choose its name.",
                       keys: [59, 60, 62]),
        ]),
        SightLevel(id: 2, title: "Treble clef notes", detail: "Read the notes your right hand plays.", stages: [
            SightStage(id: .init(level: 2, stage: 1), title: "Landmark notes",
                       detail: "Middle C, treble G and treble C.",
                       lesson: "Learn three landmarks first and read everything else from them. Middle C is on the ledger line below the staff. G is the second line up: the line the treble clef curls around. Treble C is the third space, an octave above Middle C.",
                       keys: [60, 67, 72]),
            SightStage(id: .init(level: 2, stage: 2), title: "Line notes",
                       detail: "E, G, B, D, F on the five lines.",
                       lesson: "From the bottom up, the treble lines are E, G, B, D and F. Remember them as Every Good Boy Deserves Fruit.",
                       keys: [64, 67, 71, 74, 77]),
            SightStage(id: .init(level: 2, stage: 3), title: "Space notes",
                       detail: "F, A, C, E in the spaces, then everything.",
                       lesson: "From the bottom up, the treble spaces spell FACE. Now mix lines and spaces, from Middle C up to the G above the staff.",
                       keys: [65, 69, 72, 76]),
        ]),
        SightLevel(id: 3, title: "Bass clef notes", detail: "Read the notes your left hand plays.", stages: [
            SightStage(id: .init(level: 3, stage: 1), title: "Landmark notes",
                       detail: "Bass G, bass C, bass F and Middle C.",
                       lesson: "The bass clef's two dots sit either side of the F line, the fourth line up. G is the bottom line, C is the second space, and Middle C is on the ledger line just above the staff.",
                       keys: [43, 48, 53, 60]),
            SightStage(id: .init(level: 3, stage: 2), title: "Line notes",
                       detail: "G, B, D, F, A on the five lines.",
                       lesson: "From the bottom up, the bass lines are G, B, D, F and A. Remember them as Good Boys Do Fine Always.",
                       keys: [43, 47, 50, 53, 57]),
            SightStage(id: .init(level: 3, stage: 3), title: "Space notes",
                       detail: "A, C, E, G in the spaces, then everything.",
                       lesson: "From the bottom up, the bass spaces are A, C, E and G: All Cows Eat Grass. Now mix lines and spaces, from low F up to Middle C.",
                       keys: [45, 48, 52, 55]),
        ]),
        SightLevel(id: 4, title: "Note values", detail: "How long each note lasts.", stages: [
            SightStage(id: .init(level: 4, stage: 1), title: "Whole, half, quarter",
                       detail: "Tell the three basic notes apart.",
                       lesson: "A note's shape says how long it lasts, counted in beats. A whole note is an open oval with no stem: 4 beats. A half note is open with a stem: 2 beats. A quarter note is filled in with a stem: 1 beat.",
                       keys: []),
            SightStage(id: .init(level: 4, stage: 2), title: "Counting beats",
                       detail: "How many beats does each note get?",
                       lesson: "Count the beats each note lasts. A dot after a note adds half its length again, so a dotted half note lasts 2 + 1 = 3 beats.",
                       keys: []),
            SightStage(id: .init(level: 4, stage: 3), title: "Eighth notes",
                       detail: "Add the eighth note: half a beat.",
                       lesson: "An eighth note is a filled note with a stem and a flag. It lasts half a beat, so two eighth notes fill one beat. Count them \"1 and\".",
                       keys: []),
        ]),
        SightLevel(id: 5, title: "Rests", detail: "Silence has a length too.", stages: [
            SightStage(id: .init(level: 5, stage: 1), title: "Whole & half rests",
                       detail: "The two little blocks.",
                       lesson: "A rest is a beat of silence. The whole rest and half rest are both small blocks: the whole rest hangs down from the fourth line (4 beats), the half rest sits on top of the middle line (2 beats). Think: whole is heavy and hangs, half is light and sits.",
                       keys: []),
            SightStage(id: .init(level: 5, stage: 2), title: "Quarter & eighth rests",
                       detail: "The squiggle and the flag.",
                       lesson: "The quarter rest is a tall squiggle: 1 beat of silence. The eighth rest looks like a 7 with a dot on its arm: half a beat.",
                       keys: []),
            SightStage(id: .init(level: 5, stage: 3), title: "Notes and rests",
                       detail: "How long is the sound or the silence?",
                       lesson: "Each rest matches a note value: whole 4 beats, half 2, quarter 1, eighth ½. Read notes and rests together and count how long each one lasts.",
                       keys: []),
        ]),
    ]

    public static func stage(_ id: SightStageID) -> SightStage? {
        levels.first { $0.id == id.level }?.stages.first { $0.id == id }
    }

    public static func level(_ id: Int) -> SightLevel? { levels.first { $0.id == id } }
}
