import Foundation

/// A song a new learner picks at setup as the reward at the end of their first unit.
/// All public domain, and all playable in Middle C position with the right hand.
public struct GoalSong: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    /// One line on why it's a good first song.
    public var blurb: String
    /// The notes it uses, lowest first.
    public var notes: [NoteName]

    public init(id: String, title: String, blurb: String, notes: [NoteName]) {
        self.id = id
        self.title = title
        self.blurb = blurb
        self.notes = notes
    }
}

public enum GoalSongs {
    public static let all: [GoalSong] = [
        GoalSong(id: "mary", title: "Mary Had a Little Lamb",
                 blurb: "Gentle and familiar: you'll play its first line by page 4.",
                 notes: notes("C4", "D4", "E4", "G4")),
        GoalSong(id: "hotCrossBuns", title: "Hot Cross Buns",
                 blurb: "Short and bouncy: the classic very first tune.",
                 notes: notes("C4", "D4", "E4")),
        GoalSong(id: "odeToJoy", title: "Ode to Joy",
                 blurb: "Beethoven's melody, simplified to five fingers.",
                 notes: notes("C4", "D4", "E4", "F4", "G4")),
        GoalSong(id: "jingleBells", title: "Jingle Bells (chorus)",
                 blurb: "The chorus everyone knows, in five fingers.",
                 notes: notes("C4", "D4", "E4", "F4", "G4")),
    ]

    /// The default when none is chosen.
    public static let defaultID = "mary"

    public static func song(_ id: String?) -> GoalSong? {
        all.first { $0.id == id }
    }

    private static func notes(_ names: String...) -> [NoteName] {
        names.compactMap { NoteName($0) }
    }
}
