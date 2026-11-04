#if os(macOS)
import XCTest
import PianoGraderCore
import PianoLessons
import PianoPadState
@testable import PianoPad

/// The keys answer a sight-reading note question: clicked on screen, typed or played.
final class SightReadingKeysTests: XCTestCase {
    private var sandbox: AppDataSandbox!

    override func setUp() { sandbox = AppDataSandbox("SightKeys") }
    override func tearDown() { sandbox.remove() }

    private func quizSession(page: String) -> PlaySession {
        let session = sandbox.session()
        session.learner = nil
        session.learners = [Learner(name: "Test", kind: .adult)]
        session.needsLearnerPick = false
        session.tab = .learn
        session.tabChanged()
        let runner = session.lessonRunner
        runner.openSightPage(page)
        // Past the lesson card to the quiz.
        for _ in 0..<3 where runner.shownBlock?.kind != .sightReading { runner.skip() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        return session
    }

    func testClickingTheRightKeyAnswersANoteQuestion() throws {
        let session = quizSession(page: "sight-1.3")
        let runner = session.lessonRunner
        XCTAssertEqual(runner.shownBlock?.kind, .sightReading)
        let quiz = runner.sightReading
        let pitch = try XCTUnwrap(quiz.question?.playPitch, "Middle C questions are answered at the keys")
        session.mouseDown(on: pitch)
        session.mouseUp()
        XCTAssertNotNil(quiz.quiz?.response, "The click should answer the question")
        XCTAssertEqual(quiz.quiz?.response?.isCorrect, true)
    }

    /// Lines and spaces aren't answered at the keys: a click says so instead of doing nothing.
    func testAKeyOnAButtonsOnlyQuestionSaysToUseTheButtons() throws {
        let session = quizSession(page: "sight-1.1")
        let runner = session.lessonRunner
        XCTAssertEqual(runner.shownBlock?.kind, .sightReading)
        XCTAssertNil(runner.sightReading.question?.playPitch)
        session.mouseDown(on: 60)
        session.mouseUp()
        XCTAssertNil(runner.sightReading.quiz?.response)
        XCTAssertEqual(runner.feedback?.kind, .hint)
        XCTAssertTrue(runner.feedback?.text.contains("buttons") == true)
        // Answering clears it.
        runner.sightReading.answer(runner.sightReading.question?.correctAnswer.id)
        XCTAssertNil(runner.feedback)
    }
}
#endif
