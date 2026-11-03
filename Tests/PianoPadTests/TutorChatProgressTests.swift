#if os(macOS)
import XCTest
import PianoAI
import PianoGraderCore
import PianoLessons
import PianoPadState
@testable import PianoPad

/// C4: progress, trends, today's plan and dated goals, from the tutor chat.
private final class ProgressChat: TutorChatClient, @unchecked Sendable {
    var replies: [TutorChatReply] = []
    var calls: [(TutorChatContext, String)] = []
    func reply(history: [TutorChatTurn], context: TutorChatContext, question: String) async throws -> TutorChatReply {
        calls.append((context, question))
        return replies.isEmpty ? TutorChatReply(onTopic: true, reply: "Keep counting steadily.") : replies.removeFirst()
    }
}

private struct NoPlan: LessonPlanModel {
    func propose(system: String, user: String, schemaName: String, schema: String) async throws -> String { "{}" }
}

final class TutorChatProgressTests: XCTestCase {
    private var sandbox: AppDataSandbox!
    override func setUp() { sandbox = AppDataSandbox("ChatProgress") }
    override func tearDown() { sandbox.remove() }

    @MainActor private func player() throws -> PlaySession {
        let session = sandbox.session()
        session.addLearner(name: "Adult", kind: .adult)
        let notes = [60, 62, 64, 65, 67, 69, 71, 72].enumerated().map { i, pitch in
            NoteEvent(pitch: pitch, onset: Double(i) * 2, offset: Double(i) * 2 + 0.5,
                      onsetBeats: Double(i) * 4, offsetBeats: Double(i) * 4 + 1)
        }
        let file = sandbox.folder.appendingPathComponent("Eight bars.mid")
        try MIDIFile.write(notes: notes).write(to: file)
        XCTAssertTrue(session.loadReference(file))
        session.setModeNow(.wait)
        session.tutorChatClient = ProgressChat()
        session.tutorPlanModel = NoPlan()
        session.makeTutorFeedbackClient = { throw ModelError.missingKey(.meta) }
        return session
    }

    @MainActor private func settle(_ session: PlaySession) async {
        for _ in 0..<300 {
            try? await Task.sleep(nanoseconds: 5_000_000)
            if !session.tutorChatBusy && !session.tutorPlanning { return }
        }
        XCTFail("Tutor did not settle")
    }

    @MainActor func testPlanIsSavedTickedRestoredAndRunsIntoItsFirstStep() async throws {
        let session = try player()
        let fake = ProgressChat()
        fake.replies = [.init(onTopic: true, reply: "Here's today.", actions: [
            .init(kind: .planSession, minutes: 15, planSteps: ["Warm up: bar 4 slowly", "Bars 3–4 in time", "Whole piece once"]),
            .init(kind: .practicePassage, fromBar: 4, toBar: 4),
        ])]
        session.tutorChatClient = fake
        session.sendTutorChat("Plan 15 minutes for me")
        await settle(session)
        XCTAssertEqual(session.tutorChatSessionPlan?.steps.map(\.text), ["Warm up: bar 4 slowly", "Bars 3–4 in time", "Whole piece once"])
        XCTAssertTrue(session.tutorChatFocus.contains("bars 4–4"), "the plan went on to its first step")
        session.toggleTutorChatPlanStep(0)
        XCTAssertTrue(session.tutorChatContext(for: "What's next?").progress.contains("[x] Warm up: bar 4 slowly; [ ] Bars 3–4 in time"))
        session.pauseTutorChatCoaching(); session.endTutoring()

        let again = sandbox.session()
        XCTAssertTrue(again.loadReference(try XCTUnwrap(session.referenceURL)))
        XCTAssertEqual(again.tutorChatSessionPlan?.steps.first?.done, true)
        again.setTutorChatSessionPlan(nil)
        XCTAssertNil(sandbox.session().tutorChatMemory(for: try XCTUnwrap(again.learner?.id)).plan())
    }

    @MainActor func testBadPlansAndGoalDatesChangeNothing() throws {
        let session = try player()
        XCTAssertTrue(session.applyTutorChatAction(.init(kind: .planSession, minutes: 15, planSteps: ["Only one"])).contains("Nothing was saved"))
        XCTAssertTrue(session.applyTutorChatAction(.init(kind: .planSession, minutes: 500, planSteps: ["a", "b"])).contains("Nothing was saved"))
        XCTAssertNil(session.tutorChatSessionPlan)
        XCTAssertTrue(session.applyTutorChatAction(.init(kind: .setGoal, goal: "Play it", goalDate: "next week")).contains("YYYY-MM-DD"))
        XCTAssertTrue(session.applyTutorChatAction(.init(kind: .setGoal, goal: "Play it", goalDate: "2001-01-01")).contains("two years"))
        XCTAssertNil(session.learnerSettings.tutorGoal)
    }

    @MainActor func testDatedGoalIsSavedAndShownWithDaysLeft() throws {
        let session = try player()
        let day = Calendar.current.date(byAdding: .day, value: 30, to: Calendar.current.startOfDay(for: Date()))!
        let text = { () -> String in
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: day)
        }()
        let outcome = session.applyTutorChatAction(.init(kind: .setGoal, goal: "Play Ode to Joy at full speed", goalDate: text))
        XCTAssertTrue(outcome.contains("by "))
        XCTAssertEqual(session.learnerSettings.tutorGoalDate, day)
        XCTAssertTrue(session.tutorChatContext(for: "Am I on track?").goal.contains("(30 days from today)"))
        // A new goal without a date drops the old date.
        _ = session.applyTutorChatAction(.init(kind: .setGoal, goal: "Play it smoothly"))
        XCTAssertNil(session.learnerSettings.tutorGoalDate)
    }

    @MainActor func testTrendsAndProgressComeFromSavedTakes() throws {
        let session = try player()
        XCTAssertTrue(session.tutorChatContext(for: "How am I doing?").trends.contains("No saved takes"))
        for _ in 0..<2 {
            session.mouseDown(on: 61); session.mouseUp() // a wrong note in bar 1
            session.finishTake()
        }
        let context = session.tutorChatContext(for: "How am I doing?")
        XCTAssertTrue(context.trends.contains("2 graded takes"), context.trends)
        XCTAssertTrue(context.trends.contains("bar 1, 2 of 2 takes"), context.trends)
        XCTAssertTrue(context.trends.contains("not evidence the piece is ready"), context.trends)
        XCTAssertTrue(context.progress.contains("This week:"))
        XCTAssertTrue(context.progress.contains("Coach's next lesson"))
        XCTAssertTrue(context.prompt.contains("This piece over time:"))
    }
}
#endif
