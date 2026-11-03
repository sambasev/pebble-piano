#if os(macOS)
import XCTest
import PianoAI
import PianoGraderCore
import PianoLessons
import PianoPadState
@testable import PianoPad

private final class CoachingChat: TutorChatClient, @unchecked Sendable {
    var replies: [TutorChatReply] = []
    var calls: [(TutorChatContext, String)] = []
    var delay: UInt64 = 0
    func reply(history: [TutorChatTurn], context: TutorChatContext, question: String) async throws -> TutorChatReply {
        calls.append((context, question))
        let reply = replies.isEmpty ? TutorChatReply(onTopic: true, reply: "Keep counting steadily.") : replies.removeFirst()
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        return reply
    }
}

private struct QuickPlan: LessonPlanModel {
    func propose(system: String, user: String, schemaName: String, schema: String) async throws -> String {
        // A malformed proposal deliberately exercises the checked local fallback.
        return "{}"
    }
}

final class TutorChatCoachingTests: XCTestCase {
    private var sandbox: AppDataSandbox!
    override func setUp() { sandbox = AppDataSandbox("ChatCoaching") }
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
        session.tutorChatClient = CoachingChat()
        session.tutorPlanModel = QuickPlan()
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

    @MainActor func testMIDIQuestionIncludesActualScoreRhythmFingeringAndImage() throws {
        let session = try player()
        let context = session.tutorChatContext(for: "Help me learn bar 4")
        XCTAssertTrue(context.score.contains("Bar 4"))
        XCTAssertTrue(context.score.contains("F4"))
        XCTAssertTrue(context.score.contains("duration 1.0q"))
        XCTAssertTrue(context.score.contains("finger"))
        XCTAssertNotNil(context.scoreImage)
        XCTAssertTrue(context.screen.contains("waiting"))
        XCTAssertTrue(context.availableLessons.contains("p1"))
        XCTAssertTrue(context.grades.contains("No graded takes"))
    }

    @MainActor func testPracticeActionSelectsOnlyTheRequestedBarWithoutReplacingTheScore() throws {
        let session = try player()
        let outcome = session.applyTutorChatAction(.init(kind: .practicePassage, fromBar: 4, toBar: 4, tempoPercent: 55, mode: .wait))
        XCTAssertTrue(outcome.contains("Started bars 4–4"))
        XCTAssertEqual(session.tutorAttempt?.measures, 4...4)
        XCTAssertEqual(session.reference?.notes.map(\.pitch), [65])
        XCTAssertEqual(session.score?.measures.count, 8)
        XCTAssertEqual(session.tempoPercent, 55)
        XCTAssertEqual(session.mode, .wait)
        XCTAssertTrue(session.tutorChatCoaching)
        session.endTutoring()
    }

    @MainActor func testGraderFeedsBackAndTheModelStartsTheNextRepetition() async throws {
        let session = try player()
        let fake = CoachingChat()
        fake.replies = [
            .init(onTopic: true, reply: "Let's practise bar 4.", action: .init(kind: .practicePassage, fromBar: 4, toBar: 4, tempoPercent: 50)),
            .init(onTopic: true, reply: "You found F4. Repeat it with steady counting.", action: .init(kind: .practicePassage, fromBar: 4, toBar: 4, tempoPercent: 65)),
        ]
        session.tutorChatClient = fake
        session.sendTutorChat("Loop bar 4 slowly so I can learn it")
        await settle(session)
        session.mouseDown(on: 65); session.mouseUp()
        session.finishTake()
        await settle(session)
        XCTAssertEqual(fake.calls.count, 2)
        XCTAssertTrue(fake.calls[1].0.grades.contains("printed bars [4]"))
        XCTAssertTrue(fake.calls[1].0.grades.contains("Notes correct 1/1"))
        XCTAssertTrue(fake.calls[1].0.grades.contains("Timing not assessed"))
        XCTAssertEqual(session.tutorAttempt?.measures, 4...4)
        XCTAssertEqual(session.tempoPercent, 65)
        XCTAssertEqual(session.phase, .waiting)
        XCTAssertTrue(session.tutorChat.turns.contains { $0.role == .app && $0.text.contains("Take graded") })
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    @MainActor func testSavedLessonsAndRecentGradesAreIncludedOnlyForTheActiveLearner() throws {
        let session = try player()
        let id = try XCTUnwrap(session.learner?.id)
        let history = session.learnerStore.history(for: id)
        try history.recordPageComplete(unit: "u1", page: "p1", stars: 2, flaggedBlocks: [1])
        try history.recordSession(.init(started: Date(), pages: ["p1"], completedPages: ["p1"], notesLearned: ["C"], stars: 2))
        session.mouseDown(on: 60); session.mouseUp(); session.finishTake()
        let context = session.tutorChatContext(for: "What should I practise?")
        XCTAssertTrue(context.history.contains("completed 1 times"))
        XCTAssertTrue(context.history.contains("new notes [\"C\"]"))
        XCTAssertTrue(context.grades.contains("Saved take"))
        session.addLearner(name: "Other", kind: .adult)
        let other = session.tutorChatContext(for: "What have I practised?")
        XCTAssertFalse(other.history.contains("completed 1 times"))
        XCTAssertFalse(other.grades.contains("Saved take"))
    }

    @MainActor func testGoalPersistsPerLearnerAndOldSettingsStillDecode() throws {
        let session = try player()
        _ = session.applyTutorChatAction(.init(kind: .setGoal, goal: "Play this piece smoothly at 110 BPM"))
        let id = try XCTUnwrap(session.learner?.id)
        XCTAssertEqual(session.learnerStore.settings(for: id).tutorGoal, "Play this piece smoothly at 110 BPM")
        XCTAssertTrue(session.tutorChatContext(for: "What next?").goal.contains("110 BPM"))
        session.addLearner(name: "Other", kind: .adult)
        XCTAssertFalse(session.tutorChatGoal.contains("110 BPM"))
        XCTAssertNil(try JSONDecoder().decode(LearnerSettings.self, from: Data("{}".utf8)).tutorGoal)
    }

    @MainActor func testInvalidActionsAndRecordingDoNotReplaceTheMusic() throws {
        let session = try player()
        for action in [TutorChatAction(kind: .practicePassage, fromBar: 999, toBar: 999),
                       .init(kind: .practicePassage, fromBar: 1, toBar: 2, tempoPercent: -5),
                       .init(kind: .practicePassage, fromBar: 1, toBar: 2, hand: .left)] {
            _ = session.applyTutorChatAction(action)
            XCTAssertNil(session.tutor)
            XCTAssertEqual(session.reference?.notes.count, 8)
            XCTAssertFalse(session.tutorChatCoaching)
        }
        session.mouseDown(on: 60); session.mouseUp()
        let result = session.applyTutorChatAction(.init(kind: .practicePassage, fromBar: 4, toBar: 4))
        XCTAssertTrue(result.contains("still recording"))
        XCTAssertEqual(session.noteCount, 1)
        XCTAssertEqual(session.phase, .recording)
    }

    @MainActor func testRefusedModelResponseCannotRunAnAction() async throws {
        let session = try player()
        let fake = CoachingChat()
        fake.replies = [.init(onTopic: false, reply: "", action: .init(kind: .practicePassage, fromBar: 4, toBar: 4))]
        session.tutorChatClient = fake
        session.sendTutorChat("Not music")
        await settle(session)
        XCTAssertNil(session.tutor)
        XCTAssertFalse(session.tutorChatCoaching)
    }

    @MainActor func testLateReplyCannotStartPracticeForAnotherLearner() async throws {
        let session = try player()
        let fake = CoachingChat()
        fake.delay = 80_000_000
        fake.replies = [.init(onTopic: true, reply: "Practise.", action: .init(kind: .practicePassage, fromBar: 4, toBar: 4))]
        session.tutorChatClient = fake
        session.sendTutorChat("Practise bar 4")
        try await Task.sleep(nanoseconds: 10_000_000)
        session.addLearner(name: "Child", kind: .child)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(session.tutor)
        XCTAssertFalse(session.tutorChatCoaching)
        XCTAssertTrue(session.tutorChat.turns.isEmpty)
    }

    @MainActor func testLateReplyCannotReplaceAManuallyOpenedPiece() async throws {
        let session = try player()
        let fake = CoachingChat()
        fake.delay = 80_000_000
        fake.replies = [.init(onTopic: true, reply: "Practise.", action: .init(kind: .practicePassage, fromBar: 4, toBar: 4))]
        session.tutorChatClient = fake
        session.sendTutorChat("Practise bar 4")
        try await Task.sleep(nanoseconds: 10_000_000)
        session.loadReference(try XCTUnwrap(PlaySession.bundledResource("Examples/five-finger.mid")), remember: false)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(session.tutor)
        XCTAssertFalse(session.tutorChatCoaching)
        XCTAssertTrue(session.tutorChat.turns.isEmpty)
    }

    @MainActor func testGradeWaitsForAnInFlightAnswerThenUsesItsCapturedEvidence() async throws {
        let session = try player()
        let fake = CoachingChat()
        fake.delay = 80_000_000
        session.tutorChatClient = fake
        _ = session.applyTutorChatAction(.init(kind: .practicePassage, fromBar: 4, toBar: 4))
        session.sendTutorChat("How should I count this?")
        try await Task.sleep(nanoseconds: 10_000_000)
        session.mouseDown(on: 65); session.mouseUp(); session.finishTake()
        XCTAssertNotNil(session.tutorChatPendingObservation)
        await settle(session)
        XCTAssertEqual(fake.calls.count, 2)
        XCTAssertTrue(fake.calls[1].0.grades.contains("Notes correct 1/1"))
        XCTAssertNil(session.tutorChatPendingObservation)
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    @MainActor func testSilentTakeDoesNotStartAnAutomaticModelLoop() async throws {
        let session = try player()
        let fake = CoachingChat()
        session.tutorChatClient = fake
        _ = session.applyTutorChatAction(.init(kind: .practicePassage, fromBar: 4, toBar: 4, mode: .timed))
        session.finishTake()
        await settle(session)
        XCTAssertTrue(fake.calls.isEmpty)
        XCTAssertTrue(session.tutorHeardNothing)
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    @MainActor func testPausingPreventsAutomaticFollowUpAndStopKeepsRecordedTake() async throws {
        let session = try player()
        let fake = CoachingChat()
        session.tutorChatClient = fake
        _ = session.applyTutorChatAction(.init(kind: .practicePassage, fromBar: 4, toBar: 4))
        session.mouseDown(on: 65); session.mouseUp()
        _ = session.applyTutorChatAction(.init(kind: .stop))
        await settle(session)
        XCTAssertFalse(session.tutorChatCoaching)
        XCTAssertNil(session.tutor)
        XCTAssertTrue(fake.calls.isEmpty)
        let history = session.learnerStore.history(for: try XCTUnwrap(session.learner?.id))
        XCTAssertEqual(history.allTakes().count, 1)
    }

    @MainActor func testStockLessonOpensWithoutLosingTheConversation() async throws {
        let session = try player()
        session.sendTutorChat("Teach me the basics")
        await settle(session)
        let before = session.tutorChat.turns
        let result = session.applyTutorChatAction(.init(kind: .openLesson, lessonID: "p1"))
        await settle(session)
        XCTAssertTrue(result.contains("Opened"))
        XCTAssertEqual(session.lessonRunner.page?.id, "p1")
        XCTAssertEqual(session.tab, .learn)
        XCTAssertEqual(session.tutorChat.turns, before)
        XCTAssertTrue(session.tutorChatCoaching)
        session.pauseTutorChatCoaching()
        session.lessonRunner.leave()
    }

    @MainActor func testStartingPieceLessonPlansAndStartsFirstStep() async throws {
        let session = try player()
        let fake = CoachingChat()
        fake.replies = [.init(onTopic: true, reply: "Follow the demonstration.", action: .init(kind: .continueLesson))]
        session.tutorChatClient = fake
        let result = session.applyTutorChatAction(.init(kind: .startLesson))
        XCTAssertTrue(result.contains("Planning"))
        await settle(session)
        XCTAssertNotNil(session.tutor?.plan)
        XCTAssertFalse(fake.calls.isEmpty)
        XCTAssertTrue(session.isAuditioning || session.tutorAttempt != nil)
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    func testStructuredAdapterDecodesActionAndIncludesAllEvidence() async throws {
        let endpoint = ModelEndpoint(provider: .meta, baseURL: URL(string: "https://api.meta.ai/v1")!, apiKey: "test")
        let client = ModelClient(endpoint: endpoint, log: UsageLog(printsToConsole: false), transport: { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let messages = body["messages"] as! [[String: Any]]
            let parts = messages.last!["content"] as! [[String: Any]]
            XCTAssertEqual(parts.count, 2)
            XCTAssertTrue((parts[0]["text"] as! String).contains("Bar 4: F4"))
            XCTAssertTrue((parts[0]["text"] as! String).contains("Play at 110 BPM"))
            let reply = #"{"on_topic":true,"reply":"Let's practise bar 4.","action":{"kind":"practicePassage","fromBar":4,"toBar":4,"hand":"LR","tempoPercent":60,"mode":"wait","lessonID":null,"goal":null}}"#
            return (try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": reply]]]]),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        var context = TutorChatContext()
        context.score = "Bar 4: F4"
        context.goal = "Play at 110 BPM"
        context.scoreImage = Data([1])
        let reply = try await ModelTutorChatClient(client: client, model: "test").reply(history: [], context: context, question: "Help bar 4")
        XCTAssertEqual(reply.action?.kind, .practicePassage)
        XCTAssertEqual(reply.action?.fromBar, 4)
    }

    /// Opt-in only: checks the deployed tutor's multimodal schema and ability to act on score data.
    @MainActor func testLiveTutorReadsTheScoreAndRequestsTheCorrectPassage() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PIANOAI_LIVE"] == "1", "set PIANOAI_LIVE=1 and MODEL_API_KEY to call Meta")
        let key = try XCTUnwrap(ProcessInfo.processInfo.environment["MODEL_API_KEY"])
        let session = try player()
        let client = ModelTutorChatClient(client: ModelClient(endpoint: .init(provider: .meta, baseURL: ModelProvider.meta.defaultBaseURL!, apiKey: key)), model: MetaModels.spark)
        let context = session.tutorChatContext(for: "Explain bar 4")
        let explanation = try await client.reply(history: [], context: context,
                                                  question: "Explain exactly which notes and rhythms are in bar 4 of the open score. Do not start playback.")
        print("Tutor score explanation:", explanation.reply)
        XCTAssertTrue(explanation.onTopic)
        XCTAssertTrue(explanation.reply.contains("F"))
        XCTAssertNil(explanation.action)
        let practice = try await client.reply(history: [], context: context,
                                               question: "Loop just bar 4 at 60% speed, all notes together, in note-by-note wait mode. My goal is to play this piece smoothly.")
        print("Tutor practice request:", practice.action?.kind.rawValue ?? "none", practice.action?.fromBar ?? -1, practice.action?.toBar ?? -1)
        XCTAssertTrue(practice.onTopic)
        XCTAssertEqual(practice.action?.kind, .practicePassage)
        XCTAssertEqual(practice.action?.fromBar, 4)
        XCTAssertEqual(practice.action?.toBar, 4)
        XCTAssertEqual(practice.action?.tempoPercent, 60)
    }
}
#endif
