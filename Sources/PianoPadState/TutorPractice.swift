import Foundation

/// Time spent learning a piece with the AI tutor, as `.tutor` practice sessions.
///
/// Activity is starting the tutor and each graded take. Time between two activities counts,
/// up to `maxCredit` (a long take, or reading the tutor's advice); a gap of `idleLimit` or more
/// starts a new session, as in Learn.
public struct TutorPracticeTracker {
    public static let idleLimit: TimeInterval = 20 * 60
    public static let maxCredit: TimeInterval = 5 * 60
    public private(set) var current: PracticeSession?
    public private(set) var learner: UUID?
    private var lastActivity: Date?

    public init() {}

    /// Tutoring started (or something else happened worth counting) for `learner`.
    public mutating func activity(learner: UUID, at date: Date) {
        if self.learner != learner || lastActivity.map({ date.timeIntervalSince($0) >= Self.idleLimit }) ?? true {
            current = PracticeSession(started: date, kind: .tutor, activeSeconds: 0)
            self.learner = learner
        } else if let last = lastActivity, var s = current {
            s.activeSeconds = (s.activeSeconds ?? 0) + min(Self.maxCredit, max(0, date.timeIntervalSince(last)))
            s.ended = max(s.ended, date)
            current = s
        }
        lastActivity = date
    }

    /// A take with the tutor was graded. Returns the session to save.
    public mutating func take(piece: String, learner: UUID, at date: Date) -> PracticeSession? {
        activity(learner: learner, at: date)
        guard var s = current else { return nil }
        s.takes += 1
        if !s.pieces.contains(piece) { s.pieces.append(piece) }
        current = s
        return s
    }
}
