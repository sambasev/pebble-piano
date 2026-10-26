import Foundation

/// Someone learning on this Mac. Called `Learner`, not `Profile`, because `PianoProfile`
/// already means the microphone calibration in PianoGraderCore.
public struct Learner: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case adult, child
    }

    /// A rough starting point, asked for (optionally) when the learner is added.
    public enum Level: String, Codable, CaseIterable, Sendable {
        /// Just starting.
        case beginner
        /// Knows the basics.
        case basics
    }

    public let id: UUID
    public var name: String
    /// An SF Symbol name or an emoji.
    public var avatar: String
    public var kind: Kind
    public var level: Level?
    public let createdAt: Date

    public static let defaultAvatar = "person.crop.circle"

    public init(id: UUID = UUID(), name: String, avatar: String = Learner.defaultAvatar,
                kind: Kind, level: Level? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.kind = kind
        self.level = level
        self.createdAt = createdAt
    }
}
