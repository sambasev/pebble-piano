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
        XCTAssertTrue(context.screen.contains("Section: practice (the open piece's score"))
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
                       .init(kind: .practicePassage, fromBar: 1, toBar: 2, tempoPercent: -5)] {
            _ = session.applyTutorChatAction(action)
            XCTAssertNil(session.tutor)
            XCTAssertEqual(session.reference?.notes.count, 8)
            XCTAssertFalse(session.tutorChatCoaching)
        }
        session.mouseDown(on: 60); session.mouseUp()
        session.mouseDown(on: 62); session.mouseUp()
        let result = session.applyTutorChatAction(.init(kind: .practicePassage, fromBar: 4, toBar: 4))
        XCTAssertTrue(result.contains("still recording"))
        XCTAssertEqual(session.noteCount, 2)
        XCTAssertEqual(session.phase, .recording)
    }

    /// A stray note (the mic hearing something) starts a take, but it isn't a performance:
    /// the tutor's demo or passage replaces it instead of being refused.
    @MainActor func testAStrayNoteDoesNotBlockTheTutor() throws {
        let session = try player()
        session.mouseDown(on: 60); session.mouseUp()
        XCTAssertEqual(session.phase, .recording)
        let result = session.applyTutorChatAction(.init(kind: .practicePassage, fromBar: 4, toBar: 4, mode: .wait))
        XCTAssertTrue(result.contains("Started bars 4–4"), result)
        XCTAssertEqual(session.noteCount, 0)
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    /// Asked to hear a passage mid-take, the tutor plays it: the half-played take is set
    /// aside rather than the learner being told to grade it first.
    @MainActor func testListeningMidTakeSetsTheTakeAsideAndPlays() throws {
        let session = try player()
        session.mouseDown(on: 60); session.mouseUp()
        session.mouseDown(on: 62); session.mouseUp()
        XCTAssertEqual(session.phase, .recording)
        let result = session.applyTutorChatAction(.init(kind: .listenPassage, fromBar: 1, toBar: 2, tempoPercent: 50))
        XCTAssertTrue(result.contains("set aside"), result)
        XCTAssertFalse(result.contains("still recording"), result)
        XCTAssertTrue(session.tutorChatActionRan)
        XCTAssertEqual(session.noteCount, 0)
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    /// The reply said "I'll practise bar 4" but a real take was recording: the app asks once
    /// more and the bubble says what really happened.
    @MainActor func testARefusedActionGetsAnHonestReply() async throws {
        let session = try player()
        let chat = CoachingChat()
        chat.replies = [
            TutorChatReply(onTopic: true, reply: "Let's practise bar 4 slowly now.",
                           actions: [.init(kind: .practicePassage, fromBar: 4, toBar: 4, tempoPercent: 50)]),
            TutorChatReply(onTopic: true, reply: "I couldn't play it: your take is still recording. Grade it first.",
                           suggestions: ["Play it now"]),
        ]
        session.tutorChatClient = chat
        session.mouseDown(on: 60); session.mouseUp()
        session.mouseDown(on: 62); session.mouseUp()
        session.sendTutorChat("Let me practise bar 4 slowly")
        await settle(session)
        XCTAssertEqual(chat.calls.count, 2)
        XCTAssertTrue(chat.calls[1].1.contains("could not do what your last reply said"), chat.calls[1].1)
        XCTAssertTrue(chat.calls[1].1.contains("still recording"))
        let tutor = session.tutorChat.turns.filter { $0.role == .tutor }
        XCTAssertEqual(tutor.map(\.text), ["I couldn't play it: your take is still recording. Grade it first."])
        XCTAssertEqual(session.tutorChat.suggestions, ["Play it now"])
        XCTAssertEqual(session.phase, .recording)
    }

    /// An action that runs needs no second call.
    @MainActor func testARunActionIsNotReasked() async throws {
        let session = try player()
        let chat = CoachingChat()
        chat.replies = [TutorChatReply(onTopic: true, reply: "I'll set up bar 4; play when ready.",
                                       actions: [.init(kind: .practicePassage, fromBar: 4, toBar: 4, mode: .wait)])]
        session.tutorChatClient = chat
        session.sendTutorChat("Help me with bar 4")
        await settle(session)
        XCTAssertEqual(chat.calls.count, 1)
        XCTAssertEqual(session.tutorChat.turns.last(where: { $0.role == .tutor })?.text, "I'll set up bar 4; play when ready.")
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    /// Found by the live eval: on a one-track file, "right hand" can only mean its notes.
    @MainActor func testOneHandOnAOneTrackFileUsesAllItsNotes() throws {
        let session = try player()
        let outcome = session.applyTutorChatAction(.init(kind: .practicePassage, fromBar: 1, toBar: 2, hand: .right))
        XCTAssertTrue(outcome.contains("all its notes (the file has one track)"), outcome)
        XCTAssertNotNil(session.tutor)
        XCTAssertNil(session.tutorAttempt?.hand ?? session.tutor?.exercise.hand)
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    /// Opening the chat turns coaching on; closing it turns that default off again, and the
    /// ✦ button's choice is remembered for next time.
    @MainActor func testCoachingIsOnByDefaultWhileTheChatIsOpen() throws {
        let key = PlaySession.tutorChatCoachesByDefaultKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        let session = try player()
        XCTAssertFalse(session.tutorChatCoaching)

        session.applyTutorChatCoachingDefault()
        XCTAssertTrue(session.tutorChatCoaching, "on from the start")
        session.leaveTutorChat()
        XCTAssertFalse(session.tutorChatCoaching, "the default stops when the chat closes")

        session.applyTutorChatCoachingDefault()
        session.setTutorChatCoaching(false)
        XCTAssertFalse(session.tutorChatCoaching)
        session.applyTutorChatCoachingDefault()
        XCTAssertFalse(session.tutorChatCoaching, "pausing is remembered")

        session.setTutorChatCoaching(true)
        session.leaveTutorChat()
        XCTAssertTrue(session.tutorChatCoaching, "turned on by hand: it stays on")
        session.pauseTutorChatCoaching(); session.endTutoring()
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

    @MainActor func testPlanRunsItsNextStepAfterTheGradeWithoutAskingTheModel() async throws {
        let session = try player()
        let fake = CoachingChat()
        fake.replies = [.init(onTopic: true, reply: "Bar 4 first, then bars 3–4.", actions: [
            .init(kind: .setGoal, goal: "Play it smoothly"),
            .init(kind: .practicePassage, fromBar: 4, toBar: 4),
            .init(kind: .practicePassage, fromBar: 3, toBar: 4),
        ], suggestions: ["Slower please"])]
        session.tutorChatClient = fake
        session.sendTutorChat("Teach me bar 4, then put it with bar 3")
        await settle(session)
        XCTAssertEqual(session.learnerSettings.tutorGoal, "Play it smoothly")
        XCTAssertTrue(session.tutorChatFocus.contains("bars 4–4"))
        XCTAssertEqual(session.tutorChatQueuedActions.map(\.fromBar), [3])
        XCTAssertEqual(session.tutorChat.suggestions, ["Slower please"])
        session.mouseDown(on: 65); session.mouseUp(); session.finishTake()
        await settle(session)
        XCTAssertEqual(fake.calls.count, 1)
        XCTAssertTrue(session.tutorChatQueuedActions.isEmpty)
        XCTAssertTrue(session.tutorChatFocus.contains("bars 3–4"))
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    @MainActor func testAFailedStepDropsTheRestOfThePlan() async throws {
        let session = try player()
        let fake = CoachingChat()
        fake.replies = [.init(onTopic: true, reply: "Let's go.", actions: [
            .init(kind: .practicePassage, fromBar: 999, toBar: 999),
            .init(kind: .practicePassage, fromBar: 4, toBar: 4),
        ])]
        session.tutorChatClient = fake
        session.sendTutorChat("Practise the end")
        await settle(session)
        XCTAssertNil(session.tutor)
        XCTAssertTrue(session.tutorChatQueuedActions.isEmpty)
        XCTAssertEqual(session.tutorChat.turns.last?.text, PlaySession.skippedSteps(1))
    }

    @MainActor func testANewQuestionOrStopCancelsAQueuedPlan() async throws {
        let session = try player()
        let fake = CoachingChat()
        fake.replies = [.init(onTopic: true, reply: "Two steps.", actions: [
            .init(kind: .practicePassage, fromBar: 4, toBar: 4),
            .init(kind: .practicePassage, fromBar: 3, toBar: 4),
        ])]
        session.tutorChatClient = fake
        session.sendTutorChat("Bar 4 then bars 3–4")
        await settle(session)
        XCTAssertEqual(session.tutorChatQueuedActions.count, 1)
        session.sendTutorChat("Actually, what does legato mean?")
        XCTAssertTrue(session.tutorChatQueuedActions.isEmpty)
        await settle(session)
        fake.replies = [.init(onTopic: true, reply: "Stopping.", actions: [.init(kind: .stop), .init(kind: .practicePassage, fromBar: 4, toBar: 4)])]
        session.sendTutorChat("Stop")
        await settle(session)
        XCTAssertTrue(session.tutorChatQueuedActions.isEmpty)
        XCTAssertFalse(session.tutorChatCoaching)
        XCTAssertEqual(session.tutorChat.turns.last?.text, PlaySession.skippedSteps(1))
        session.endTutoring()
    }

    @MainActor func testSuggestionsAreOfferedForAnAdviceReply() async throws {
        let session = try player()
        let fake = CoachingChat()
        fake.replies = [.init(onTopic: true, reply: "Count four beats.", suggestions: ["Play bar 4 for me", "Practise bar 4"])]
        session.tutorChatClient = fake
        session.sendTutorChat("How do I count bar 4?")
        await settle(session)
        XCTAssertEqual(session.tutorChat.suggestions, ["Play bar 4 for me", "Practise bar 4"])
        session.sendTutorChat(session.tutorChat.suggestions[1])
        XCTAssertEqual(session.tutorChat.turns.last?.text, "Practise bar 4")
        await settle(session)
    }

    @MainActor func testConversationReopensWithThePieceAndANoteIsKeptWhenItEnds() async throws {
        let session = try player()
        session.sendTutorChat("How do I count bar 4?")
        await settle(session)
        let file = try XCTUnwrap(session.referenceURL)

        // Relaunch: the same learner opening the same piece sees the conversation again.
        let again = sandbox.session()
        XCTAssertEqual(again.learner?.id, session.learner?.id)
        XCTAssertTrue(again.loadReference(file))
        XCTAssertEqual(again.tutorChat.turns.map(\.text), ["How do I count bar 4?", "Keep counting steadily."])

        // Another piece ends it: the next conversation starts empty, with a note about this one.
        again.tutorChatClient = CoachingChat()
        XCTAssertTrue(again.loadReference(try XCTUnwrap(PlaySession.bundledResource("Examples/five-finger.mid")), remember: false))
        XCTAssertTrue(again.tutorChat.turns.isEmpty)
        let memory = again.tutorChatMemory(for: try XCTUnwrap(again.learner?.id))
        for _ in 0..<100 where memory.notes().isEmpty { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(memory.notes().map(\.text), ["Asked: How do I count bar 4?"])
        XCTAssertTrue(again.tutorChatContext(for: "What did we do last time?").previousSessions.contains("How do I count bar 4?"))
        XCTAssertTrue(again.loadReference(file))
        XCTAssertTrue(again.tutorChat.turns.isEmpty)
    }

    @MainActor func testSwitchingLearnersKeepsEachConversationForTheirReturn() async throws {
        let session = try player()
        let first = try XCTUnwrap(session.learner)
        session.sendTutorChat("What is legato?")
        await settle(session)
        session.addLearner(name: "Other", kind: .adult)
        XCTAssertTrue(session.tutorChat.turns.isEmpty)
        session.switchLearner(to: first.id)
        XCTAssertEqual(session.tutorChat.turns.first?.text, "What is legato?")
        XCTAssertTrue(session.tutorChatMemory(for: first.id).notes().isEmpty)
    }

    @MainActor func testSilentTakeDoesNotStartAnAutomaticModelLoop() async throws {
        let session = try player()
        let fake = CoachingChat()
        session.tutorChatClient = fake
        _ = session.applyTutorChatAction(.init(kind: .practicePassage, fromBar: 4, toBar: 4, mode: .timed))
        XCTAssertTrue(session.tutorChatAwaitingStart)
        XCTAssertEqual(session.phase, .waiting)
        XCTAssertFalse(session.isPlayingAlong)
        session.startPreparedTutorChatExercise()
        XCTAssertEqual(session.phase, .recording)
        session.finishTake()
        await settle(session)
        XCTAssertTrue(fake.calls.isEmpty)
        XCTAssertNil(session.report)
        XCTAssertTrue(session.tutorChatAwaitingStart)
        XCTAssertEqual(session.phase, .waiting)
        XCTAssertTrue(session.learnerStore.history(for: try XCTUnwrap(session.learner?.id)).allTakes().isEmpty)
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    @MainActor func testStopKeepsTheTakeUngradedUntilTheLearnerFinishesIt() async throws {
        let session = try player()
        let fake = CoachingChat()
        session.tutorChatClient = fake
        _ = session.applyTutorChatAction(.init(kind: .practicePassage, fromBar: 4, toBar: 4))
        session.mouseDown(on: 65); session.mouseUp()
        _ = session.applyTutorChatAction(.init(kind: .stop))
        await settle(session)
        XCTAssertFalse(session.tutorChatCoaching)
        XCTAssertEqual(session.noteCount, 1)
        XCTAssertNil(session.report)
        XCTAssertTrue(session.tutorChatOffersGrade)
        XCTAssertTrue(fake.calls.isEmpty)
        let history = session.learnerStore.history(for: try XCTUnwrap(session.learner?.id))
        XCTAssertTrue(history.allTakes().isEmpty)
        session.finishTutorChatTake()
        XCTAssertEqual(history.allTakes().count, 1)
        XCTAssertFalse(session.tutorChatCoaching)
        session.endTutoring()
    }

    @MainActor func testTimedPracticeWaitsForStartEvenAfterAResponse() async throws {
        let session = try player()
        let fake = CoachingChat()
        fake.replies = [.init(onTopic: true, reply: "Ready for bar 4.", action: .init(kind: .practicePassage, fromBar: 4, toBar: 4, tempoPercent: 100, mode: .timed))]
        session.tutorChatClient = fake
        session.sendTutorChat("Practise bar 4 in time")
        await settle(session)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(session.phase, .waiting)
        XCTAssertFalse(session.isPlayingAlong)
        XCTAssertEqual(session.noteCount, 0)
        XCTAssertNil(session.report)
        XCTAssertTrue(session.tutorChatAwaitingStart)
        XCTAssertEqual(fake.calls.count, 1)
        session.mouseDown(on: 65); session.mouseUp()
        XCTAssertEqual(session.noteCount, 0, "Notes before Start are warm-up, not a take")
        _ = session.applyTutorChatAction(.init(kind: .gradeTake))
        XCTAssertNil(session.report)
        XCTAssertFalse(session.tutorChatOffersGrade)
        XCTAssertEqual(fake.calls.count, 1)
        session.startPreparedTutorChatExercise()
        XCTAssertTrue(session.isPlayingAlong)
        XCTAssertFalse(session.tutorChatAwaitingStart)
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    @MainActor func testPausingTheCoachDoesNotMakeAnEmptyTimedRunGradeable() async throws {
        let session = try player()
        _ = session.applyTutorChatAction(.init(kind: .practicePassage, fromBar: 4, toBar: 4, mode: .timed))
        session.startPreparedTutorChatExercise()
        session.pauseTutorChatCoaching()
        session.finishTake()
        XCTAssertNil(session.report)
        XCTAssertEqual(session.phase, .waiting)
        XCTAssertTrue(session.tutorChatAwaitingStart)
        session.endTutoring()
    }

    @MainActor func testTempoChangePreservesPassageAndDoesNotGradeAPartialTake() async throws {
        let session = try player()
        _ = session.applyTutorChatAction(.init(kind: .practicePassage, fromBar: 3, toBar: 4, tempoPercent: 100))
        session.mouseDown(on: 64); session.mouseUp()
        let result = session.applyTutorChatAction(.init(kind: .setTempo, tempoPercent: 50))
        XCTAssertTrue(result.contains("50%"))
        XCTAssertEqual(session.phase, .recording)
        XCTAssertEqual(session.noteCount, 1)
        XCTAssertNil(session.report)
        XCTAssertEqual(session.tutorAttempt?.measures, 3...4)
        XCTAssertEqual(session.tutorAttempt?.tempoPercent, 50)
        XCTAssertEqual(session.tutor?.exercise.tempoPercent, 50)
        XCTAssertTrue(session.learnerStore.history(for: try XCTUnwrap(session.learner?.id)).allTakes().isEmpty)
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    @MainActor func testModelGradeRequestCannotFinishAPartialTakeByItself() async throws {
        let session = try player()
        _ = session.applyTutorChatAction(.init(kind: .practicePassage, fromBar: 3, toBar: 4))
        session.mouseDown(on: 64); session.mouseUp()
        let fake = CoachingChat()
        fake.replies = [.init(onTopic: true, reply: "I'll grade first.", action: .init(kind: .gradeTake))]
        session.tutorChatClient = fake
        session.sendTutorChat("Can you reduce the tempo?")
        await settle(session)
        XCTAssertEqual(session.phase, .recording)
        XCTAssertEqual(session.noteCount, 1)
        XCTAssertNil(session.report)
        XCTAssertTrue(session.tutorChatOffersGrade)
        XCTAssertEqual(fake.calls.count, 1)
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    /// "Let me play it" with no action: the app asks once for the action, and it runs.
    @MainActor func testAPromiseWithoutAnActionIsAskedForItsAction() async throws {
        let session = try player()
        let chat = CoachingChat()
        chat.replies = [
            TutorChatReply(onTopic: true, reply: "Let me play bars 1–2 for you slowly."),
            TutorChatReply(onTopic: true, reply: "Let me play bars 1–2 for you slowly.",
                           actions: [.init(kind: .listenPassage, fromBar: 1, toBar: 2, tempoPercent: 50)]),
        ]
        session.tutorChatClient = chat
        session.sendTutorChat("Can you play bars 1 and 2?")
        await settle(session)
        XCTAssertEqual(chat.calls.count, 2)
        XCTAssertEqual(chat.calls[1].1, TutorChatInstructions.missingAction)
        XCTAssertTrue(session.tutorChatActionResults.contains { $0.contains("bars 1–2") }, session.tutorChatActionResults.joined())
        XCTAssertEqual(session.tutorChat.turns.filter { $0.role == .tutor }.count, 1)
        session.stopAudition(); session.pauseTutorChatCoaching(); session.endTutoring()
    }

    /// Plain advice isn't mistaken for a promise: no second call.
    @MainActor func testAdviceWithoutAPromiseNeedsNoAction() async throws {
        let session = try player()
        let chat = CoachingChat()
        chat.replies = [TutorChatReply(onTopic: true, reply: "Let me show you a trick: count 1-and-2 out loud.")]
        session.tutorChatClient = chat
        session.sendTutorChat("How do I count this?")
        await settle(session)
        XCTAssertEqual(chat.calls.count, 1)
    }

    /// In a Learn lesson the tutor can still play bars; the lesson's own exercise stays.
    @MainActor func testListeningInALessonPlaysTheBars() throws {
        let session = try player()
        let file = sandbox.folder.appendingPathComponent("Eight bars.mid")
        session.loadLessonBlock(midi: file, piece: .passage("lesson"), mode: .wait, tempo: nil, countInBeats: 4)
        XCTAssertTrue(session.isInLesson)
        let notes = session.reference?.notes.count
        let result = session.applyTutorChatAction(.init(kind: .listenPassage, fromBar: 1, toBar: 1, tempoPercent: 60))
        XCTAssertFalse(result.contains("Open a piece in Practice"), result)
        try XCTSkipUnless(session.isAuditioning, "No piano audio output is available: \(result)")
        XCTAssertTrue(result.contains("Playing bars 1–1"), result)
        XCTAssertEqual(session.reference?.notes.count, notes, "The lesson's music is left as it was")
        XCTAssertNil(session.tutor)
        session.stopAudition()
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
