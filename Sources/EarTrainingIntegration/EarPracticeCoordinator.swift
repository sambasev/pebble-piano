#if canImport(Combine)
import Combine
import Foundation
import EarTrainingUI
import PianoGraderCore
import PianoPadState

@MainActor private final class LearnerEarStore: EarProgressStore {
    let history: LearnerHistory?
    init(_ history: LearnerHistory?) { self.history = history }
    func load() -> EarProgress { EarProgress.decode(history?.earTrainingProgress()) }
    func save(_ progress: EarProgress) throws {
        if let history { try history.saveEarTrainingProgress(JSONEncoder().encode(progress)) }
    }
}

/// The app-facing bridge: the reusable quiz UI knows nothing about learner folders or streaks.
@MainActor public final class EarPracticeCoordinator: ObservableObject {
    @Published public private(set) var session: EarTrainingSession
    @Published public private(set) var sessionIdentity = UUID()
    @Published public var summary: PracticeSession?
    @Published public private(set) var historyError: String?
    public private(set) var learnerID: UUID?
    private let playback: any EarPlayback
    private let now: () -> Date
    private var history: LearnerHistory?
    private var tracker = EarPracticeTracker()
    private var visible = false
    private var foreground = true
    private var lastCheckpoint = Date.distantPast
    private var pendingHistory: [(UUID, LearnerHistory, PracticeSession)] = []
    // A failed progress save remains available if the learner switches away and back.
    private var unsaved: [UUID: EarTrainingSession] = [:]

    public init(playback: any EarPlayback, now: @escaping () -> Date = Date.init) {
        self.playback = playback; self.now = now
        session = EarTrainingSession(playback: playback, store: LearnerEarStore(nil))
    }

    public func bind(learnerID: UUID?, history: LearnerHistory?) {
        guard self.learnerID != learnerID || self.history == nil else { return }
        endPractice(showSummary: false)
        session.overview()
        session.onActivity = nil; session.onQuizCompleted = nil
        if let old = self.learnerID, session.hasUnsavedProgress { unsaved[old] = session }
        self.learnerID = learnerID; self.history = history
        summary = nil
        if let learnerID, let retained = unsaved.removeValue(forKey: learnerID) {
            session = retained
        } else {
            session = EarTrainingSession(playback: playback, store: LearnerEarStore(history))
        }
        sessionIdentity = UUID()
        connectEvents()
    }

    private func connectEvents() {
        session.onActivity = { [weak self] activity in
            guard let self, self.visible, self.learnerID != nil, self.foreground else { return }
            if self.tracker.isIdle(at: self.now()) { self.endPractice(showSummary: false) }
            self.tracker.setForeground(self.foreground, at: self.now())
            self.tracker.interact(at: self.now(), answered: activity != .listening)
            self.checkpoint()
        }
        session.onQuizCompleted = { [weak self] result, id in
            guard let self, self.visible, self.learnerID != nil else { return }
            self.tracker.complete(EarQuizSummary(id: id, level: result.stage.level, stage: result.stage.stage,
                                                correct: result.correct, total: result.total), at: self.now())
            self.checkpoint(force: true)
        }
    }

    public func arrive() { visible = true; tracker.setForeground(foreground, at: now()) }
    public func leave() { session.stop(); visible = false; endPractice(showSummary: true) }
    public func close() { session.stop(); visible = false; endPractice(showSummary: false); retryHistory() }

    public func setForeground(_ value: Bool) {
        tracker.setForeground(value, at: now())
        foreground = value
        checkpoint(force: true)
    }

    public func tick() {
        retryHistory()
        guard visible else { return }
        if tracker.isIdle(at: now()) {
            session.stop()
            endPractice(showSummary: true)
        } else {
            tracker.tick(at: now())
            checkpoint()
        }
    }

    public func retryHistory() {
        let retry = pendingHistory
        pendingHistory.removeAll()
        for (id, history, value) in retry { persist(value, learnerID: id, history: history) }
        if pendingHistory.isEmpty, historyError != nil { historyError = nil }
    }

    private func checkpoint(force: Bool = false) {
        guard let id = learnerID, let history, let value = tracker.current,
              force || now().timeIntervalSince(lastCheckpoint) >= 5 else { return }
        persist(value, learnerID: id, history: history)
        lastCheckpoint = now()
    }

    private func persist(_ value: PracticeSession, learnerID: UUID, history: LearnerHistory) {
        // Replace queued checkpoints too, so retrying can never overwrite a newer result.
        pendingHistory.removeAll { $0.0 == learnerID && $0.2.id == value.id }
        do { try history.recordSession(value) }
        catch {
            pendingHistory.append((learnerID, history, value))
            historyError = "Couldn't save practice history: \(error.localizedDescription). Retry saving."
        }
    }

    private func endPractice(showSummary: Bool) {
        guard let value = tracker.finish(at: now()), let id = learnerID, let history else { return }
        persist(value, learnerID: id, history: history)
        if showSummary { summary = value }
    }

    /// Call after the history reset succeeds. Never write the discarded session back to disk.
    public func didReset(learnerID id: UUID) {
        unsaved.removeValue(forKey: id)
        pendingHistory.removeAll { $0.0 == id }
        guard learnerID == id else { return }
        session.stop()
        session.onActivity = nil; session.onQuizCompleted = nil
        tracker = EarPracticeTracker()
        tracker.setForeground(foreground, at: now())
        summary = nil; historyError = nil
        session = EarTrainingSession(playback: playback, store: LearnerEarStore(history))
        sessionIdentity = UUID()
        connectEvents()
    }

    /// Includes this sitting once, even if its most recent checkpoint is already on disk.
    public func today() -> [PracticeSession] {
        PracticeTotals.today((history?.sessions() ?? []) + [tracker.current].compactMap { $0 }, now: now())
    }
    public var streakDays: Int { WeeklyStreak.daysThisWeek(history?.sessions() ?? [], now: now()) }
}
#endif
