import Foundation

/// A piece the learner opened recently.
public struct RecentPiece: Codable, Equatable, Sendable {
    public var id: PieceID
    /// Security-scoped bookmark to the file. The sandboxed app can't reopen a file from a path
    /// saved in an earlier launch, so this is what reopens it. Nil for book passages.
    public var bookmark: Data?
    /// For display, and as a fallback in the unsandboxed (Swift package) build.
    public var path: String?
    public var title: String?

    public init(id: PieceID, bookmark: Data? = nil, path: String? = nil, title: String? = nil) {
        self.id = id
        self.bookmark = bookmark
        self.path = path
        self.title = title
    }
}

/// Settings that belong to one learner. Device-wide settings (volumes, mic gate, calibration)
/// stay in `UserDefaults` and Application Support.
///
/// `strictness` and `missMode` are the raw values of `PlaySession`'s enums, and
/// `customPlayAlong` is a JSON-encoded `Rubric.PlayAlong`, so this target needs neither the
/// app nor PianoGraderCore. Missing keys decode as defaults, so settings files written by an
/// older build still load.
public struct LearnerSettings: Codable, Equatable, Sendable {
    public var strictness: String
    /// JSON-encoded `Rubric.PlayAlong`; nil means the app's default (gentle).
    public var customPlayAlong: Data?
    public var missMode: String
    /// Newest first, at most `maxRecentPieces`.
    public var recentPieces: [RecentPiece]
    /// The teacher chosen at setup: "alex" (relaxed) or "kriti" (strict). nil: not chosen yet.
    public var persona: String?
    /// The goal song chosen at setup (a `GoalSong` ID such as "mary").
    public var goalSong: String?
    /// How the learner plays: an `InputSource` raw value ("midi", "microphone",
    /// "computerKeyboard"). nil: not asked.
    public var inputSource: String?
    /// When setup (onboarding) was finished; nil for learners added another way.
    public var onboardedAt: Date?
    /// Lesson pages: the Pebbles dance under the keyboard. nil: on (the default); the learner,
    /// or a grown-up for a child, can turn them off.
    public var dancers: Bool?
    /// The Practice tab's mode as last chosen in its picker: "wait" or "playAlong".
    /// nil: not chosen yet (Wait).
    public var practiceMode: String?

    public var showsDancers: Bool { dancers ?? true }

    public static let defaultStrictness = "rubric"
    public static let defaultMissMode = "replayBar"
    public static let maxRecentPieces = 10

    public init(strictness: String = LearnerSettings.defaultStrictness, customPlayAlong: Data? = nil,
                missMode: String = LearnerSettings.defaultMissMode, recentPieces: [RecentPiece] = [],
                persona: String? = nil, goalSong: String? = nil, inputSource: String? = nil, onboardedAt: Date? = nil,
                dancers: Bool? = nil, practiceMode: String? = nil) {
        self.strictness = strictness
        self.customPlayAlong = customPlayAlong
        self.missMode = missMode
        self.recentPieces = recentPieces
        self.persona = persona
        self.goalSong = goalSong
        self.inputSource = inputSource
        self.onboardedAt = onboardedAt
        self.dancers = dancers
        self.practiceMode = practiceMode
    }

    private enum CodingKeys: String, CodingKey {
        case strictness, customPlayAlong, missMode, recentPieces, persona, goalSong, inputSource, onboardedAt, dancers, practiceMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strictness = try c.decodeIfPresent(String.self, forKey: .strictness) ?? Self.defaultStrictness
        customPlayAlong = try c.decodeIfPresent(Data.self, forKey: .customPlayAlong)
        missMode = try c.decodeIfPresent(String.self, forKey: .missMode) ?? Self.defaultMissMode
        recentPieces = try c.decodeIfPresent([RecentPiece].self, forKey: .recentPieces) ?? []
        persona = try c.decodeIfPresent(String.self, forKey: .persona)
        goalSong = try c.decodeIfPresent(String.self, forKey: .goalSong)
        inputSource = try c.decodeIfPresent(String.self, forKey: .inputSource)
        onboardedAt = try c.decodeIfPresent(Date.self, forKey: .onboardedAt)
        dancers = try c.decodeIfPresent(Bool.self, forKey: .dancers)
        practiceMode = try c.decodeIfPresent(String.self, forKey: .practiceMode)
    }

    /// Moves `piece` to the front (replacing any entry with the same ID) and keeps the newest
    /// `maxRecentPieces`.
    public mutating func remember(_ piece: RecentPiece) {
        recentPieces.removeAll { $0.id == piece.id }
        recentPieces.insert(piece, at: 0)
        if recentPieces.count > Self.maxRecentPieces {
            recentPieces.removeLast(recentPieces.count - Self.maxRecentPieces)
        }
    }

    public mutating func forget(_ id: PieceID) {
        recentPieces.removeAll { $0.id == id }
    }
}
