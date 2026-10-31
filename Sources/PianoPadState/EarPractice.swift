import Foundation

/// Pure activity clock. A click/listen/answer starts practice; opening a tab does not.
/// Time is credited only in the foreground, within 60 seconds of a meaningful interaction.
public struct EarPracticeTracker {
    public static let idleLimit: TimeInterval = 20 * 60
    public static let activeWindow: TimeInterval = 60
    public private(set) var current: PracticeSession?
    public private(set) var lastActivity: Date?
    private var lastTick: Date?
    private var foreground = true
    public init() {}

    public mutating func tick(at date: Date) {
        defer { lastTick = date }
        guard var session = current, let previous = lastTick, let lastActivity, date >= previous else { return }
        if foreground {
            let until = min(date, lastActivity.addingTimeInterval(Self.activeWindow))
            let seconds = max(0, until.timeIntervalSince(previous))
            session.activeSeconds = (session.activeSeconds ?? 0) + seconds
            if seconds > 0 { session.ended = max(session.ended, until) }
        }
        current = session
    }

    public mutating func setForeground(_ value: Bool, at date: Date) {
        tick(at: date)
        foreground = value
    }

    public mutating func interact(at date: Date, answered: Bool = false) {
        tick(at: date)
        if current == nil { current = PracticeSession(started: date, kind: .earTraining, activeSeconds: 0) }
        lastActivity = date
        lastTick = date
        current?.ended = date
        if answered { current?.earQuestionsAnswered += 1 }
    }

    public mutating func complete(_ quiz: EarQuizSummary, at date: Date) {
        interact(at: date)
        guard current?.earQuizzes.contains(where: { $0.id == quiz.id }) == false else { return }
        current?.earQuizzes.append(quiz)
    }

    public func isIdle(at date: Date) -> Bool {
        lastActivity.map { date.timeIntervalSince($0) >= Self.idleLimit } ?? false
    }

    public mutating func finish(at date: Date) -> PracticeSession? {
        tick(at: date)
        let result = current
        current = nil; lastTick = nil; lastActivity = nil
        return result
    }
}

extension LearnerHistory {
    var earTrainingURL: URL { folder.appendingPathComponent("ear-training.json") }

    /// Opaque versioned data keeps PianoPadState independent of the ear-training engine.
    public func earTrainingProgress() -> Data? { try? Data(contentsOf: earTrainingURL) }
    public func saveEarTrainingProgress(_ data: Data) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: earTrainingURL, options: .atomic)
    }
}
