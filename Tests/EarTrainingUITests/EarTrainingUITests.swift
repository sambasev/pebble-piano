#if canImport(Combine)
import XCTest
import PianoGraderCore
@testable import EarTrainingUI

@MainActor private final class TestOutput: EarNoteOutput {
    var log: [String] = []
    func noteOn(pitch: Int, velocity: Int) { log.append("on:\(pitch)") }
    func noteOff(pitch: Int) { log.append("off:\(pitch)") }
    func allNotesOff() { log.append("allOff") }
}

@MainActor private final class TestEvent: EarScheduledEvent {
    let time: Double
    let action: @MainActor () -> Void
    var cancelled = false
    init(time: Double, action: @escaping @MainActor () -> Void) { self.time = time; self.action = action }
    func cancel() { cancelled = true }
}

@MainActor private final class TestScheduler: EarEventScheduler {
    var events: [TestEvent] = []
    func schedule(after seconds: Double, action: @escaping @MainActor () -> Void) -> any EarScheduledEvent {
        let event = TestEvent(time: seconds, action: action)
        events.append(event)
        return event
    }
}

@MainActor private final class TestPlayback: EarPlayback {
    var sequences: [[NoteEvent]] = []
    var completions: [@MainActor (Result<Void, EarPlaybackError>) -> Void] = []
    var stops = 0
    func play(_ notes: [NoteEvent], completion: @escaping @MainActor (Result<Void, EarPlaybackError>) -> Void) {
        sequences.append(notes); completions.append(completion)
    }
    func stop() { stops += 1 }
    func finish() { completions.last?(.success(())) }
}

@MainActor private final class TestStore: EarProgressStore {
    var value = EarProgress()
    var saves = 0
    func load() -> EarProgress { value }
    func save(_ progress: EarProgress) { value = progress; saves += 1 }
}

final class EarTrainingUITests: XCTestCase {
    @MainActor func testCancelledCallbacksCannotSoundOrCutOffNewPlayback() async {
        let scheduler = TestScheduler(), output = TestOutput()
        let player = EarPlaybackController(scheduler: scheduler, makeOutput: { output })
        var oldCompletions = 0, newCompletions = 0
        player.play([NoteEvent(pitch: 60, onset: 0, offset: 1)]) { _ in oldCompletions += 1 }
        let stale = scheduler.events
        stale.first!.action()
        player.play([NoteEvent(pitch: 60, onset: 0, offset: 2)]) { _ in newCompletions += 1 }
        let current = Array(scheduler.events.dropFirst(stale.count))
        current.first!.action()
        let before = output.log
        // Intentionally invoke cancelled callbacks to simulate an already-dequeued timer.
        stale.forEach { $0.action() }
        XCTAssertEqual(output.log, before)
        XCTAssertTrue(stale.allSatisfy(\.cancelled))
        XCTAssertEqual(oldCompletions, 0)
        current.dropFirst().forEach { $0.action() }
        XCTAssertEqual(newCompletions, 1)
        XCTAssertEqual(output.log.suffix(2), ["off:60", "allOff"])
        current.last!.action()
        XCTAssertEqual(newCompletions, 1)
    }

    @MainActor func testStopCancelsFutureChordAndAllSoundingNotes() async {
        let scheduler = TestScheduler(), output = TestOutput()
        let player = EarPlaybackController(scheduler: scheduler, makeOutput: { output })
        player.play([NoteEvent(pitch: 60, onset: 0, offset: 1), NoteEvent(pitch: 64, onset: 2, offset: 3)]) { _ in
            XCTFail("Stopped playback must not complete")
        }
        scheduler.events.first!.action()
        player.stop()
        let log = output.log
        scheduler.events.forEach { $0.action() }
        XCTAssertEqual(output.log, log)
        XCTAssertEqual(output.log.last, "allOff")
    }

    @MainActor func testAudioInitializationRetriesAndInvalidSequencesAreRejected() async {
        let scheduler = TestScheduler(), output = TestOutput()
        var attempts = 0
        let player = EarPlaybackController(scheduler: scheduler, makeOutput: {
            attempts += 1
            return attempts == 1 ? nil : output
        })
        let note = NoteEvent(pitch: 60, onset: 0, offset: 1)
        player.play([note]) { result in
            guard case .failure(.unavailable) = result else { return XCTFail("Expected audio failure") }
        }
        XCTAssertTrue(scheduler.events.isEmpty)
        player.play([note]) { _ in }
        XCTAssertEqual(attempts, 2)
        XCTAssertFalse(scheduler.events.isEmpty)
        player.play([NoteEvent(pitch: 200, onset: 0, offset: 1)]) { result in
            guard case .failure(.invalidSequence) = result else { return XCTFail("Expected validation error") }
        }
        XCTAssertTrue(scheduler.events.allSatisfy(\.cancelled))
    }

    @MainActor func testReferenceAndPartialPlaybackDoNotUnlockAnswers() async {
        let audio = TestPlayback(), store = TestStore()
        let session = EarTrainingSession(playback: audio, store: store)
        session.startQuiz(seed: 1)
        XCTAssertEqual(audio.sequences.count, 1, "Starting a quiz plays the first question by itself")
        let answer = session.question!.correctAnswer.id
        session.answer(answer)
        XCTAssertNil(session.quiz?.response)
        session.playReference(); audio.finish()
        XCTAssertFalse(session.canAnswer)
        session.playQuestion()
        let interrupted = audio.completions.last!
        session.stop(); interrupted(.success(()))
        XCTAssertFalse(session.canAnswer)
        session.playQuestion(); audio.finish()
        XCTAssertTrue(session.canAnswer)
        session.answer(answer)
        XCTAssertEqual(session.quiz?.response?.isCorrect, true)
        session.answer(session.question!.choices.first!.id)
        XCTAssertEqual(session.quiz?.responses.count, 1)
        XCTAssertEqual(store.saves, 0)
    }

    @MainActor func testQuestionPlaysReferenceFirstThenTheNote() {
        let audio = TestPlayback()
        let session = EarTrainingSession(playback: audio, store: TestStore())
        session.startQuiz(seed: 1)
        let question = session.question!
        let played = audio.sequences.last!
        XCTAssertEqual(Array(played.prefix(question.reference.count)), question.reference)
        let start = question.reference.map(\.offset).max()! + 0.45
        let stimulus = Array(played.dropFirst(question.reference.count))
        XCTAssertEqual(stimulus.map(\.pitch), question.stimulus.map(\.pitch))
        XCTAssertEqual(stimulus.first!.onset, question.stimulus.first!.onset + start, accuracy: 1e-9)
    }

    @MainActor func testAnswerMovesOnByItselfUnlessTheLearnerPlaysSomething() async throws {
        let audio = TestPlayback()
        let session = EarTrainingSession(playback: audio, store: TestStore())
        session.startQuiz(seed: 1)
        audio.finish()
        session.answer(session.question!.correctAnswer.id)
        XCTAssertEqual(session.quiz?.index, 0)
        try await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertEqual(session.quiz?.index, 1, "A correct answer moves on after a second")
        XCTAssertNil(session.quiz?.response)

        audio.finish()
        session.answer(session.question!.correctAnswer.id)
        session.playSolution() // lingering on the answer cancels the move
        try await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertEqual(session.quiz?.index, 1)
    }

    @MainActor func testNavigationRejectsOldCompletionAndRetainsNoPartialProgress() async {
        let audio = TestPlayback(), store = TestStore()
        let session = EarTrainingSession(playback: audio, store: store)
        session.startQuiz(seed: 1)
        session.playQuestion()
        let old = audio.completions.last!
        session.select(EarStageID(level: 8, stage: 3))
        old(.success(()))
        XCTAssertFalse(session.heardQuestion)
        XCTAssertFalse(session.isPlaying)
        XCTAssertNil(session.quiz)
        XCTAssertEqual(store.saves, 0)
        session.learn()
        session.playExample(session.examples[0])
        audio.finish()
        XCTAssertEqual(store.saves, 0)
    }

    @MainActor func testTenQuestionCompletionSavesOnceAndRelaunchRestoresRecommendation() async {
        let audio = TestPlayback(), store = TestStore()
        let session = EarTrainingSession(playback: audio, store: store)
        session.startQuiz(seed: 111)
        for index in 0..<10 {
            if index < 8 {
                session.playQuestion(); audio.finish()
                session.playQuestion(); audio.finish() // Replay must not reduce the score.
                session.answer(session.question!.correctAnswer.id)
                session.playSolution(); audio.finish()
            } else { session.skip() }
            XCTAssertEqual(store.saves, 0)
            session.next()
        }
        XCTAssertEqual(session.result?.correct, 8)
        XCTAssertEqual(store.saves, 1)
        XCTAssertEqual(store.value.recommendedStage, EarStageID(level: 1, stage: 2))
        session.next()
        XCTAssertEqual(store.saves, 1)
        let restored = EarTrainingSession(playback: TestPlayback(), store: store)
        XCTAssertEqual(restored.selectedStage, EarStageID(level: 1, stage: 2))
        XCTAssertEqual(restored.progress.stages["1.1"]?.bestCorrect, 8)
    }

    @MainActor func testAudioErrorRemainsRetryableAndDoesNotCountAsAListen() async {
        let audio = TestPlayback(), store = TestStore()
        let session = EarTrainingSession(playback: audio, store: store)
        session.startQuiz(seed: 1)
        session.playQuestion()
        audio.completions.last?(.failure(.unavailable))
        XCTAssertNotNil(session.error)
        XCTAssertFalse(session.canAnswer)
        session.playQuestion(); audio.finish()
        XCTAssertNil(session.error)
        XCTAssertTrue(session.canAnswer)
    }

    @MainActor func testLocalPreferencesRoundTripAndCorruptDataFallback() async {
        let name = "EarTrainingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = EarLocalProgressStore(defaults: defaults)
        var progress = EarProgress()
        var quiz = EarQuiz(questions: EarQuestionGenerator.quiz(stage: .first, seed: 0))
        for _ in 0..<10 { quiz.submit(answerID: quiz.question!.correctAnswer.id); quiz.next() }
        progress.record(quiz.result!)
        store.save(progress)
        XCTAssertEqual(store.load(), progress)
        defaults.set(Data("broken".utf8), forKey: EarLocalProgressStore.key)
        XCTAssertEqual(store.load(), EarProgress())
    }
}
#endif
