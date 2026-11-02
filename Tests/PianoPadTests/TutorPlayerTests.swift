#if os(macOS)
import XCTest
import PianoPadState
@testable import PianoPad

final class TutorPlayerTests: XCTestCase {
    private var sandbox: AppDataSandbox!

    override func setUp() { sandbox = AppDataSandbox("TutorPlayer") }
    override func tearDown() { sandbox.remove() }

    func player() -> PlaySession {
        let player = sandbox.session()
        player.learner = nil
        player.learners = [Learner(name: "Test", kind: .adult)]
        player.needsLearnerPick = false
        player.setModeNow(.wait) // Whatever the real learner last chose.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        player.loadReference(root.appendingPathComponent("Examples/ode-to-joy-c.mid"), remember: false)
        return player
    }
    func testAssessmentRemainsRunningAfterDeferredUpdates() {
        let session = player()
        session.beginTutoring()
        session.startTutorExercise()
        XCTAssertTrue(session.isPlayingAlong)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        XCTAssertTrue(session.isPlayingAlong)
        XCTAssertEqual(session.phase, .recording)
        session.endTutoring()
    }
    func testNotesAdvanceWhenCorrectKeysArePlayed() {
        let session = player()
        session.beginTutoring()
        session.tutor?.learnNotes()
        session.startTutorExercise()
        let first = session.expected
        XCTAssertFalse(first.isEmpty)
        for pitch in first { session.mouseDown(on: pitch); session.mouseUp() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertGreaterThan(session.guideProgress.done, 0)
        session.endTutoring()
    }

    /// Plays the loaded passage, leaving the last key down: its release never arrives.
    private func playWithLastKeyStuck(_ session: PlaySession) {
        for _ in 0..<200 where !session.passageComplete {
            guard let pitch = session.expected.first else { break }
            session.mouseDown(on: pitch)
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            if !session.passageComplete { session.mouseUp() }
        }
    }

    private func shortPassage() -> PlaySession {
        let session = player()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // The file opens with five empty bars, so its first notes are in bar 6.
        session.loadReference(root.appendingPathComponent("Examples/ode-to-joy-c.mid"), remember: false, measures: 6...6)
        session.mode = .wait
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return session
    }

    func testFinishedPassageGradesEvenIfAKeyNeverReleases() {
        let session = shortPassage()
        session.autoGradeHeldLimit = 2.0
        playWithLastKeyStuck(session)
        XCTAssertTrue(session.passageComplete)
        XCTAssertFalse(session.held.isEmpty, "the last key is still down")
        RunLoop.main.run(until: Date().addingTimeInterval(1.6))
        XCTAssertEqual(session.phase, .recording, "a held key gets more time than the usual delay")
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        XCTAssertEqual(session.phase, .graded)
        XCTAssertTrue(session.held.isEmpty)
    }

    func testReleasedKeysStillGradeAfterTheUsualDelay() {
        let session = shortPassage()
        playWithLastKeyStuck(session)
        session.mouseUp()
        XCTAssertTrue(session.held.isEmpty)
        RunLoop.main.run(until: Date().addingTimeInterval(PlaySession.autoGradeDelay + 0.3))
        XCTAssertEqual(session.phase, .graded)
    }

    func testResetAndNewBlockClearHeldKeys() {
        let session = shortPassage()
        session.mouseDown(on: session.expected.first!)
        XCTAssertFalse(session.held.isEmpty)
        session.resetAll()
        XCTAssertTrue(session.held.isEmpty)

        session.mouseDown(on: session.expected.first!)
        XCTAssertFalse(session.held.isEmpty)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        session.loadReference(root.appendingPathComponent("Examples/ode-to-joy-c.mid"), remember: false)
        XCTAssertTrue(session.held.isEmpty)
    }

    func testAStuckKeyDoesNotBlockTheSameKeyAfterReset() {
        let session = shortPassage()
        let pitch = session.expected.first!
        session.mouseDown(on: pitch)
        session.resetAll()
        session.mouseDown(on: pitch)
        XCTAssertTrue(session.held.contains(pitch))
        session.mouseUp()
        XCTAssertTrue(session.held.isEmpty)
    }
}
#endif

#if os(macOS)
import PianoAI
import PianoLessons
private struct FailingTutorFeedback: TutorFeedbackClient {
    func explain(context: String, question: String) async throws -> String { throw URLError(.notConnectedToInternet) }
}
private actor DelayedTutorFeedback: TutorFeedbackClient {
    private var continuation: CheckedContinuation<String, Never>?
    func explain(context: String, question: String) async throws -> String {
        await withCheckedContinuation { continuation = $0 }
    }
    func isWaiting() -> Bool { continuation != nil }
    func finish() { continuation?.resume(returning: "Old response"); continuation = nil }
}
extension TutorPlayerTests {
    @MainActor func testAskingWithoutAKeyExplainsAndKeepsGuidance() {
        let session = player()
        session.makeTutorFeedbackClient = { throw ModelError.missingKey(.meta) }
        session.beginTutoring()
        let original = session.tutorText
        session.askTutor("Tell me how that went.")
        XCTAssertNil(session.tutorNote, "Automatic comments stay quiet without a key")
        session.askTutor("What went wrong?", userAsked: true)
        XCTAssertFalse(session.tutorBusy)
        XCTAssertEqual(session.tutorText, original)
        XCTAssertEqual(session.tutorAI, "")
        XCTAssertNotNil(session.tutorNote)
        session.endTutoring()
        XCTAssertNil(session.tutorNote)
    }
    @MainActor func testOfflineFallbackPreservesGuidance() async throws {
        let session = player()
        session.beginTutoring()
        session.tutorFeedbackClient = FailingTutorFeedback()
        let original = session.tutorText
        session.askTutor("Why?")
        for _ in 0..<100 where session.tutorBusy { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(session.tutorBusy)
        XCTAssertEqual(session.tutorText, original)
        XCTAssertEqual(session.tutorAI, "")
        session.endTutoring()
    }
    @MainActor func testStaleFeedbackCannotReturnAfterLeaving() async throws {
        let session = player()
        let client = DelayedTutorFeedback()
        session.beginTutoring(); session.tutorFeedbackClient = client
        session.askTutor("Why?")
        for _ in 0..<100 {
            if await client.isWaiting() { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(session.tutorBusy)
        session.endTutoring()
        await client.finish()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNil(session.tutor)
        XCTAssertEqual(session.tutorAI, "")
        XCTAssertFalse(session.tutorBusy)
    }
}
#endif

#if os(macOS)
extension TutorPlayerTests {
    /// Time with the tutor is saved as a practice session, and its takes show in the progress overview.
    func testTutorTakeRecordsATutorSession() throws {
        let session = player()
        let learner = try XCTUnwrap(session.learners.first)
        session.learner = learner
        session.beginTutoring()
        session.tutorFeedbackClient = FailingTutorFeedback()
        session.startTutorExercise()
        session.finishTake()
        XCTAssertEqual(session.phase, .graded)
        session.endTutoring()
        let history = session.learnerStore.history(for: learner.id)
        let tutorSessions = history.sessions().filter { $0.kind == .tutor }
        XCTAssertEqual(tutorSessions.count, 1)
        XCTAssertEqual(tutorSessions.first?.takes, 1)
        XCTAssertEqual(history.overviewTakes().filter(\.tutored).count, 1)
    }

    func testSilentAssessmentOffersDrillAndRestoresPractice() throws {
        let session = player()
        let originalMode = session.mode
        let originalTempo = session.tempoPercent
        session.beginTutoring()
        session.tutorFeedbackClient = FailingTutorFeedback()
        session.startTutorExercise()
        session.finishTake()
        XCTAssertEqual(session.phase, .graded)
        XCTAssertGreaterThan(session.report?.notes.missed ?? 0, 0)
        XCTAssertEqual(session.tutor?.exercise.kind, .notes)
        session.startTutorExercise()
        XCTAssertEqual(session.mode, .wait)
        XCTAssertFalse(session.expected.isEmpty)
        session.endTutoring()
        XCTAssertEqual(session.mode, originalMode)
        XCTAssertEqual(session.tempoPercent, originalTempo)
    }

    /// An empty room mustn't loop: no model call, and the next step waits until a key or Start.
    func testSilentStepSkipsModelAndPausesAutoContinue() {
        let session = player()
        session.beginTutoring()
        session.tutorFeedbackClient = DelayedTutorFeedback()
        session.startTutorExercise()
        session.finishTake()
        XCTAssertEqual(session.phase, .graded)
        XCTAssertFalse(session.tutorBusy, "nothing was played, so the model isn't asked")
        XCTAssertTrue(session.tutorHeardNothing)
        XCTAssertNotNil(session.tutorNote)

        session.mouseDown(on: 60); session.mouseUp()
        XCTAssertFalse(session.tutorHeardNothing, "a key press means someone is there")
        session.endTutoring()
    }

    func testPlayedStepStillAsksModel() {
        let session = player()
        session.beginTutoring()
        session.tutorFeedbackClient = DelayedTutorFeedback()
        session.tutor?.learnNotes()
        session.startTutorExercise()
        guard let pitch = session.expected.first else { return XCTFail("no expected note") }
        session.mouseDown(on: pitch); session.mouseUp()
        session.finishTake()
        XCTAssertEqual(session.phase, .graded)
        XCTAssertFalse(session.tutorHeardNothing)
        XCTAssertTrue(session.tutorBusy)
        session.endTutoring()
    }

    func testPickerRemembersModeButTutorDoesNot() {
        let session = player()
        session.mode = .playAlong
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(session.learnerSettings.practiceMode, "playAlong")

        session.beginTutoring()
        session.tutor?.learnNotes()
        session.startTutorExercise()
        XCTAssertEqual(session.mode, .wait)
        XCTAssertEqual(session.learnerSettings.practiceMode, "playAlong")
        session.endTutoring()
        XCTAssertEqual(session.mode, .playAlong)
    }

    func testPracticeModeDefaultsToWait() {
        XCTAssertEqual(PlaySession.practiceMode(from: LearnerSettings()), .wait)
        XCTAssertEqual(PlaySession.practiceMode(from: LearnerSettings(practiceMode: "playAlong")), .playAlong)
        XCTAssertEqual(PlaySession.practiceMode(from: LearnerSettings(practiceMode: "nonsense")), .wait)
    }

    func testClickVolumePersistence() {
        let session = player()
        let previous = session.clickVolume
        defer { session.clickVolume = previous }

        session.clickVolume = 0.45
        XCTAssertEqual(session.clickVolume, 0.45, accuracy: 0.001)
        XCTAssertEqual(UserDefaults.standard.double(forKey: "PianoPad.volume.click"), 0.45, accuracy: 0.001)
    }
}
#endif
