import Foundation

/// What the coach needs to know about one page.
public struct CoachPageState: Equatable, Sendable {
    public var completed: Bool
    /// Started but not finished (a saved position past the first step).
    public var inProgress: Bool
    /// Best page stars; nil when the page has none or hasn't been finished.
    public var bestStars: Int?
    /// Finished with steps skipped.
    public var flagged: Bool

    public init(completed: Bool = false, inProgress: Bool = false, bestStars: Int? = nil, flagged: Bool = false) {
        self.completed = completed
        self.inProgress = inProgress
        self.bestStars = bestStars
        self.flagged = flagged
    }
}

/// What to practise next, and what a warm-up means.
public enum Coach {
    /// The page to suggest:
    /// 1. an unfinished page (started but not finished, or finished with steps skipped), the one
    ///    with the fewest stars first, then in unit order;
    /// 2. otherwise the next unlocked page;
    /// 3. once everything is done, the starred page with the fewest stars (under three), to improve.
    /// nil: everything finished with three stars.
    public static func nextPage(in unit: LessonUnit, states: [String: CoachPageState]) -> LessonPage? {
        let completed = Set(states.filter { $0.value.completed }.map(\.key))
        let unlocked = unit.pages.filter { unit.isUnlocked($0.id, completed: completed) }
        func stars(_ p: LessonPage) -> Int { states[p.id]?.bestStars ?? 0 }
        func order(_ p: LessonPage) -> Int { unit.pages.firstIndex { $0.id == p.id } ?? 0 }

        let unfinished = unlocked.filter { p in
            let s = states[p.id] ?? CoachPageState()
            return (s.inProgress && !s.completed) || (s.completed && s.flagged)
        }
        if let pick = unfinished.min(by: { (stars($0), order($0)) < (stars($1), order($1)) }) { return pick }
        if let next = unit.nextPage(completed: completed) { return next }
        let improvable = unit.pages.filter { !$0.starredBlocks.isEmpty && stars($0) < 3 }
        return improvable.min { (stars($0), order($0)) < (stars($1), order($1)) }
    }

    /// Points (0–100) a warm-up may fall below last time's score before the coach suggests
    /// reviewing that page.
    public static let warmUpDropAllowed = 20.0

    /// Whether a warm-up note score (0–1) fell far enough below last time's to suggest a review.
    public static func warmUpSuggestsReview(previous: Double, now: Double) -> Bool {
        (previous - now) * 100 > warmUpDropAllowed + 1e-9
    }
}
