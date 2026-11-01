#if os(macOS)
import XCTest
import PianoPadState
@testable import PianoPad

final class TutorPlayerTests: XCTestCase {
    func player() -> PlaySession {
        let player = PlaySession(startServices: false)
        player.learner = nil // Player tests must never save into a real learner history.
        player.learners = [Learner(name: "Test", kind: .adult)]
        player.needsLearnerPick = false
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
}
#endif
