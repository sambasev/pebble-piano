import Foundation

/// The four stages of a song page. A suggested order, not a gate: any stage can be opened,
/// so someone who knows the song can go straight to Perform.
public enum SongStage: Int, CaseIterable, Comparable, Sendable {
    /// Hear it with the keys lit.
    case listen
    /// Wait mode: the music waits for each note.
    case learn
    /// Play-along at a slower tempo; a bar with too many misses plays again.
    case practise
    /// Full speed, no stops, graded once: the only run that earns stars.
    case perform

    public static func < (a: SongStage, b: SongStage) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .listen: return "Listen"
        case .learn: return "Learn"
        case .practise: return "Practise"
        case .perform: return "Perform"
        }
    }

    public var next: SongStage? { SongStage(rawValue: rawValue + 1) }

    /// Stages that count as help when they come before a Perform run in the same visit.
    public var isHelp: Bool { self == .learn || self == .practise }
}

/// Where a learner is in one song page during one visit.
public struct SongProgress: Equatable, Sendable {
    public private(set) var current: SongStage
    /// Stages finished this visit (a listen played through, a learn or practise run graded).
    public private(set) var finished: Set<SongStage> = []

    public init(start: SongStage = .listen) {
        current = start
    }

    /// The stage to suggest next: the first one not finished.
    public var suggested: SongStage {
        SongStage.allCases.first { !finished.contains($0) } ?? .perform
    }

    /// Learn or Practise was finished this visit, so a Perform run used help.
    public var usedHelp: Bool { finished.contains { $0.isHelp } }

    public mutating func go(to stage: SongStage) {
        current = stage
    }

    /// Marks `stage` finished. Returns the stage to suggest next (nil after Perform).
    @discardableResult
    public mutating func finish(_ stage: SongStage) -> SongStage? {
        finished.insert(stage)
        return stage == .perform ? nil : stage.next
    }
}

/// How a Perform run went: what the results screen shows.
public struct SongResult: Equatable, Sendable {
    public var stars: Int
    public var summary: PerformanceSummary
    /// Stars needed to finish the page (the teacher's rule).
    public var requiredStars: Int

    public init(stars: Int, summary: PerformanceSummary, requiredStars: Int) {
        self.stars = stars
        self.summary = summary
        self.requiredStars = requiredStars
    }

    public var passed: Bool { stars >= requiredStars }
}
