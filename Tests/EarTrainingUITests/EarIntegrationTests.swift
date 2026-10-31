#if canImport(Combine)
import XCTest
import PianoGraderCore
import PianoPadState
import EarTrainingIntegration
@testable import EarTrainingUI

@MainActor private final class IntegrationAudio: EarPlayback {
    var callbacks: [@MainActor (Result<Void, EarPlaybackError>) -> Void] = []
    var stops = 0
    func play(_ notes: [NoteEvent], completion: @escaping @MainActor (Result<Void, EarPlaybackError>) -> Void) {
        callbacks.append(completion)
    }
    func stop() { stops += 1 }
    func finish() { callbacks.last?(.success(())) }
}

@MainActor private final class SequenceOutput: EarSequenceOutput {
    var position: TimeInterval?
    var starts = 0, stops = 0
    var available = true
    func start(_ notes: [NoteEvent]) -> Bool { starts += 1; return available }
    func stop() { stops += 1 }
}
@MainActor private final class SequenceEvent: EarScheduledEvent {
    let action: @MainActor () -> Void
    var cancelled = false
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    func cancel() { cancelled = true }
}
@MainActor private final class SequenceScheduler: EarEventScheduler {
    var events: [SequenceEvent] = []
    func schedule(after seconds: Double, action: @escaping @MainActor () -> Void) -> any EarScheduledEvent {
        let value = SequenceEvent(action); events.append(value); return value
    }
}

final class EarIntegrationTests: XCTestCase {
    @MainActor private func complete(_ session: EarTrainingSession, audio: IntegrationAudio, seed: UInt64 = 1) {
        session.startQuiz(seed: seed)
        for _ in 0..<10 {
            session.playQuestion(); audio.finish()
            session.answer(session.question!.correctAnswer.id)
            session.next()
        }
    }

    @MainActor func testLearnerIsolationTabResumeAndStaleCallbacks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = LearnerHistory(folder: root.appendingPathComponent("a"))
        let b = LearnerHistory(folder: root.appendingPathComponent("b"))
        let idA = UUID(), idB = UUID(), audio = IntegrationAudio()
        let coordinator = EarPracticeCoordinator(playback: audio)
        coordinator.bind(learnerID: idA, history: a); coordinator.arrive()
        coordinator.session.startQuiz(seed: 9)
        coordinator.session.playQuestion(); audio.finish()
        coordinator.session.answer(coordinator.session.question!.correctAnswer.id)
        let current = coordinator.session
        coordinator.leave(); coordinator.arrive()
        XCTAssertTrue(current === coordinator.session)
        XCTAssertEqual(coordinator.session.quiz?.responses.count, 1)
        coordinator.session.next(); coordinator.session.playQuestion()
        let oldCompletion = audio.callbacks.last!
        coordinator.bind(learnerID: idB, history: b); coordinator.arrive()
        oldCompletion(.success(()))
        XCTAssertNil(coordinator.session.quiz)
        XCTAssertFalse(coordinator.session.heardQuestion)
        XCTAssertTrue(coordinator.session.progress.stages.isEmpty)
        XCTAssertNil(b.earTrainingProgress())
        XCTAssertTrue(b.sessions().isEmpty)
        XCTAssertFalse(a.sessions().isEmpty, "Partial listening/answering earns practice credit")
        coordinator.bind(learnerID: idA, history: a); coordinator.arrive()
        XCTAssertNil(coordinator.session.quiz, "Learner switches discard unfinished quizzes")
        complete(coordinator.session, audio: audio)
        XCTAssertEqual(EarProgress.decode(a.earTrainingProgress()).stages["1.1"]?.completedQuizzes, 1)
        XCTAssertNil(b.earTrainingProgress())
        coordinator.leave(); coordinator.leave()
        XCTAssertEqual(a.sessions().flatMap(\.earQuizzes).count, 1)
    }

    @MainActor func testPracticeCheckpointsAreIdempotentAndExcludeIdleBackground() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = LearnerHistory(folder: folder)
        var time = Date(timeIntervalSince1970: 1_800_000_000)
        let audio = IntegrationAudio()
        let coordinator = EarPracticeCoordinator(playback: audio, now: { time })
        coordinator.bind(learnerID: UUID(), history: history); coordinator.arrive()
        coordinator.session.learn()
        coordinator.session.playExample(coordinator.session.examples[0]); audio.finish()
        time += 10; coordinator.tick()
        coordinator.setForeground(false)
        time += 300; coordinator.tick()
        coordinator.setForeground(true)
        coordinator.session.playExample(coordinator.session.examples[1]); audio.finish()
        time += 90; coordinator.tick()
        XCTAssertEqual(history.sessions().count, 1)
        XCTAssertEqual(history.sessions()[0].activeSeconds, 70)
        XCTAssertEqual(coordinator.today().count, 1)
        time += 1200; coordinator.tick()
        XCTAssertNotNil(coordinator.summary)
        XCTAssertTrue(coordinator.summary!.earQuizzes.isEmpty)
        XCTAssertNil(history.earTrainingProgress(), "Learning and partial quizzes do not persist scores")
        coordinator.leave()
        XCTAssertEqual(history.sessions().count, 1)
    }

    @MainActor func testResetCannotResurrectAnOldCheckpoint() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = LearnerHistory(folder: folder), audio = IntegrationAudio(), id = UUID()
        let coordinator = EarPracticeCoordinator(playback: audio)
        coordinator.bind(learnerID: id, history: history); coordinator.arrive()
        complete(coordinator.session, audio: audio)
        XCTAssertFalse(history.sessions().isEmpty)
        try history.reset(); coordinator.didReset(learnerID: id)
        coordinator.tick(); coordinator.leave(); coordinator.close()
        XCTAssertNil(history.earTrainingProgress())
        XCTAssertTrue(history.sessions().isEmpty)
        XCTAssertTrue(coordinator.session.progress.stages.isEmpty)
    }

    @MainActor func testSaveFailuresSurfaceAndRetryWithoutDuplicateQuizCredit() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("a file blocks the learner directory".utf8).write(to: folder)
        let history = LearnerHistory(folder: folder), audio = IntegrationAudio()
        let coordinator = EarPracticeCoordinator(playback: audio)
        coordinator.bind(learnerID: UUID(), history: history); coordinator.arrive()
        complete(coordinator.session, audio: audio)
        XCTAssertNotNil(coordinator.historyError)
        XCTAssertTrue(coordinator.session.hasUnsavedProgress)
        XCTAssertNotNil(coordinator.session.persistenceError)
        coordinator.session.stop()
        XCTAssertNotNil(coordinator.session.persistenceError, "Stopping audio must not erase a storage warning")
        try FileManager.default.removeItem(at: folder)
        coordinator.session.retrySave(); coordinator.retryHistory()
        XCTAssertNil(coordinator.historyError)
        XCTAssertFalse(coordinator.session.hasUnsavedProgress)
        coordinator.leave(); coordinator.retryHistory(); coordinator.close()
        XCTAssertEqual(EarProgress.decode(history.earTrainingProgress()).stages["1.1"]?.completedQuizzes, 1)
        XCTAssertEqual(history.sessions().flatMap(\.earQuizzes).count, 1)
    }

    @MainActor func testDeletedLearnerCannotBeRecreatedByAPendingRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let oldFolder = root.appendingPathComponent("old")
        try Data("blocked directory".utf8).write(to: oldFolder)
        let audio = IntegrationAudio(), id = UUID()
        let coordinator = EarPracticeCoordinator(playback: audio)
        coordinator.bind(learnerID: id, history: LearnerHistory(folder: oldFolder)); coordinator.arrive()
        complete(coordinator.session, audio: audio)
        coordinator.close()
        XCTAssertNotNil(coordinator.historyError)
        try FileManager.default.removeItem(at: oldFolder)
        coordinator.didReset(learnerID: id)
        coordinator.bind(learnerID: UUID(), history: LearnerHistory(folder: root.appendingPathComponent("new")))
        coordinator.arrive(); coordinator.retryHistory(); coordinator.tick()
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFolder.path))
    }

    @MainActor func testSequencerUsesAudioClockAndRejectsStaleCompletion() async {
        let output = SequenceOutput(), scheduler = SequenceScheduler()
        var time: TimeInterval = 0, authorized = true, completions = 0
        let playback = EarSequencedPlayback(output: output, scheduler: scheduler, clock: { time }, isAuthorized: { authorized })
        let note = NoteEvent(pitch: 60, onset: 0, offset: 1)
        playback.play([note]) { _ in completions += 1 }
        let old = scheduler.events.last!
        time = 50; output.position = 0.5
        old.action()
        XCTAssertEqual(completions, 0, "Busy UI cannot unlock answers before audio finishes")
        let cancelled = scheduler.events.last!
        playback.play([note]) { _ in completions += 1 }
        let stops = output.stops
        cancelled.action()
        XCTAssertEqual(output.stops, stops)
        XCTAssertEqual(completions, 0)
        output.position = 1.1
        scheduler.events.last!.action()
        XCTAssertEqual(completions, 1)
        playback.play([note]) { _ in XCTFail("Unauthorized playback must not finish") }
        authorized = false
        scheduler.events.last!.action()
        XCTAssertTrue(scheduler.events.last!.cancelled)
    }

    @MainActor func testSequencerFailureCanRetryAndUsesElapsedTimeAfterEngineEnds() async {
        let output = SequenceOutput(), scheduler = SequenceScheduler()
        var time: TimeInterval = 0, finished = false
        let playback = EarSequencedPlayback(output: output, scheduler: scheduler, clock: { time })
        output.available = false
        playback.play([NoteEvent(pitch: 60, onset: 0, offset: 1)]) { result in
            guard case .failure(.unavailable) = result else { return XCTFail("Expected sequencer error") }
        }
        output.available = true
        playback.play([NoteEvent(pitch: 60, onset: 0, offset: 1)]) { _ in finished = true }
        time = 1.2; output.position = nil
        scheduler.events.last!.action()
        XCTAssertTrue(finished)
    }
}
#endif
