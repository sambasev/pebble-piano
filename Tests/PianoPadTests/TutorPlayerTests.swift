#if os(macOS)
import XCTest
import PianoPadState
@testable import PianoPad

final class TutorPlayerTests: XCTestCase {
    func player() -> PlaySession {
        let player = PlaySession(startServices: false)
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
