import Foundation

/// A sticker a child earns for finishing a page: shown in place of percentages (stars stay).
public struct Sticker: Equatable, Sendable {
    /// SF Symbol name.
    public var symbol: String
    public var name: String
    /// A colour name the app maps to its palette ("accent", "success", "apricot", "lilac", "mistake").
    public var color: String

    public init(symbol: String, name: String, color: String) {
        self.symbol = symbol
        self.name = name
        self.color = color
    }
}

public enum Stickers {
    /// One per page, in order; a long unit wraps round.
    public static let all: [Sticker] = [
        Sticker(symbol: "star.fill", name: "Gold Star", color: "apricot"),
        Sticker(symbol: "hare.fill", name: "Speedy Rabbit", color: "lilac"),
        Sticker(symbol: "music.note", name: "Happy Note", color: "accent"),
        Sticker(symbol: "sun.max.fill", name: "Sunshine", color: "apricot"),
        Sticker(symbol: "leaf.fill", name: "Green Leaf", color: "success"),
        Sticker(symbol: "heart.fill", name: "Big Heart", color: "mistake"),
        Sticker(symbol: "bolt.fill", name: "Lightning", color: "apricot"),
        Sticker(symbol: "crown.fill", name: "Crown", color: "apricot"),
        Sticker(symbol: "pawprint.fill", name: "Paw Print", color: "lilac"),
        Sticker(symbol: "moon.stars.fill", name: "Moon and Stars", color: "accent"),
        Sticker(symbol: "tortoise.fill", name: "Steady Tortoise", color: "success"),
        Sticker(symbol: "gift.fill", name: "Present", color: "mistake"),
    ]

    /// The sticker for the page at `index` in its unit.
    public static func forPage(at index: Int) -> Sticker {
        all[((index % all.count) + all.count) % all.count]
    }

    /// The goal song's sticker: always the crown.
    public static let goalSong = Sticker(symbol: "crown.fill", name: "Crown", color: "apricot")

    /// A child's word for how a run went, from its stars (no percentages).
    public static func cheer(stars: Int) -> String {
        switch stars {
        case 3: return "Amazing!"
        case 2: return "Super playing!"
        case 1: return "You did it!"
        default: return "Good try! Let's have another go."
        }
    }
}

/// The "For grown-ups" panel's one tip, from simple rules.
public enum GrownUpsTip {
    public struct Facts: Equatable, Sendable {
        public var name: String
        public var minutesThisWeek: Int
        public var daysThisWeek: Int
        /// The page they seem stuck on (unfinished, or finished with steps skipped).
        public var stuckPage: String?
        /// They play on the computer keyboard rather than a piano.
        public var usesComputerKeyboard: Bool
        public var goalSong: String?

        public init(name: String, minutesThisWeek: Int, daysThisWeek: Int, stuckPage: String? = nil,
                    usesComputerKeyboard: Bool = false, goalSong: String? = nil) {
            self.name = name
            self.minutesThisWeek = minutesThisWeek
            self.daysThisWeek = daysThisWeek
            self.stuckPage = stuckPage
            self.usesComputerKeyboard = usesComputerKeyboard
            self.goalSong = goalSong
        }
    }

    /// In order: no practice yet, stuck on a page, few days this week, the computer keyboard,
    /// then an audience for the goal song.
    public static func tip(_ f: Facts) -> String {
        if f.minutesThisWeek == 0 {
            return "A good time to start: sit with \(f.name) for the first page. Ten minutes is plenty."
        }
        if let page = f.stuckPage {
            return "\(f.name) is working on \(page). Sit alongside for a few minutes: ask them to play it slowly and say each note's name out loud."
        }
        if f.daysThisWeek < 3 {
            return "Short and often works best: ten minutes on most days beats one long session a week."
        }
        if f.usesComputerKeyboard {
            return "When you can, let \(f.name) try a real piano or keyboard: the same lessons work with the microphone or Bluetooth MIDI."
        }
        if let song = f.goalSong {
            return "Ask \(f.name) to play you \(song) so far. Playing for someone builds confidence."
        }
        return "Ask \(f.name) to show you what they learned this week. Playing for someone builds confidence."
    }
}
