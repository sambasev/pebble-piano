import XCTest
@testable import PianoLessons

final class TutorAppGuideTests: XCTestCase {
    func testAppQuestionsAreRecognisedAndMusicQuestionsAreNot() {
        for q in ["It can't hear me", "How do I change my teacher?", "Where is the metronome?",
                  "Switch to my MIDI piano", "Why was that marked wrong when I played it right?"] {
            XCTAssertTrue(TutorAppGuide.isAppQuestion(q), q)
        }
        for q in ["What is a dotted half note?", "How do I count bar 4?", "Explain legato"] {
            XCTAssertFalse(TutorAppGuide.isAppQuestion(q), q)
        }
    }

    func testHelpActionsEndAPlan() {
        for kind: TutorChatAction.Kind in [.openCalibration, .switchInput, .openSettings, .markPlayedRight] {
            XCTAssertTrue(TutorChatAction(kind: kind).endsPlan)
            XCTAssertFalse(TutorChatAction(kind: kind).waitsForPlayer)
        }
    }
}
