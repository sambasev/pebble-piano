#if os(macOS)
import XCTest
import PianoAI
import PianoGraderCore
import PianoLessons
import PianoPadState
@testable import PianoPad

/// C3: generated exercises, demonstrations, highlights and the courses, from the tutor chat.
private final class DemoChat: TutorChatClient, @unchecked Sendable {
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

final class TutorChatDemoTests: XCTestCase {
    private var sandbox: AppDataSandbox!
    override func setUp() { sandbox = AppDataSandbox("ChatDemo") }
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
        session.tutorChatClient = DemoChat()
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

    @MainActor private func waitForDemo(_ session: PlaySession) async {
        for _ in 0..<600 where session.isAuditioning {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(session.isAuditioning, "The demonstration did not finish")
    }

    // MARK: practiceExercise

    @MainActor func testPracticeExerciseOpensTheGeneratedScaleWithItsFingeringAndGradesIt() async throws {
        let session = try player()
        session.tutorChat.ask("Teach me the F major scale")
        let outcome = session.applyTutorChatAction(.init(kind: .practiceExercise, hand: .right, tempoPercent: 70, mode: .wait,
                                                         exercise: "majorScale", key: "F", octaves: 1))
        XCTAssertTrue(session.tutorChatActionRan, outcome)
        XCTAssertTrue(outcome.contains("F major scale, 1 octave, right hand"), outcome)
        XCTAssertEqual(session.score?.title, "F major scale, 1 octave, right hand")
        XCTAssertEqual(session.reference?.notes.map(\.pitch), [65, 67, 69, 70, 72, 74, 76, 77, 76, 74, 72, 70, 69, 67, 65])
        XCTAssertEqual(session.tutorAttempt?.measures, 1...4)
        XCTAssertEqual(session.tempoPercent, 70)
        XCTAssertTrue(session.tutorChatCoaching)
        // The learner's question survives: opening the exercise doesn't start a new conversation.
        XCTAssertTrue(session.tutorChat.turns.contains { $0.text == "Teach me the F major scale" })
        // Standard fingering from the generator, 4 on B flat.
        XCTAssertEqual(Array(session.topStaffFingering.prefix(8)), [1, 2, 3, 4, 1, 2, 3, 4])
        XCTAssertEqual(session.fingeringNotes.first { $0.pitch == 70 }?.finger, 4)

        // The normal grader judges it.
        var played: [Int] = []
        for _ in 0..<40 where session.phase != .graded {
            guard let pitch = session.expected.first else { break }
            played.append(pitch)
            session.mouseDown(on: pitch)
            try? await Task.sleep(nanoseconds: 40_000_000)
            session.mouseUp()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(played, [65, 67, 69, 70, 72, 74, 76, 77, 76, 74, 72, 70, 69, 67, 65])
        if session.phase == .recording { session.finishTake() }
        await settle(session)
        XCTAssertNotNil(session.tutorDisplayReport)
        XCTAssertEqual(session.tutorDisplayReport?.notes.score ?? 0, 1, accuracy: 1e-9)
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    @MainActor func testHandsTogetherExerciseCanBeSplitIntoHands() throws {
        let session = try player()
        _ = session.applyTutorChatAction(.init(kind: .practiceExercise, hand: .both, exercise: "arpeggio", key: "G", octaves: 2))
        XCTAssertTrue(session.tutorChatActionRan)
        XCTAssertEqual(session.reference?.hasTwoHands, true)
        XCTAssertEqual(session.score?.staves.count, 2)
        XCTAssertTrue(session.fingeringNotes.contains { $0.hand == .left && $0.finger == 5 })
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    @MainActor func testInvalidExercisesLeaveThePieceAlone() throws {
        let session = try player()
        let before = session.reference?.notes.map(\.pitch)
        for action in [TutorChatAction(kind: .practiceExercise, exercise: "chromaticScale", key: "C"),
                       .init(kind: .practiceExercise, exercise: "majorScale", key: "H"),
                       .init(kind: .practiceExercise, exercise: "majorScale", key: nil),
                       .init(kind: .practiceExercise, exercise: "majorScale", key: "C", octaves: 3),
                       .init(kind: .practiceExercise, tempoPercent: 10, exercise: "majorScale", key: "C")] {
            let outcome = session.applyTutorChatAction(action)
            XCTAssertFalse(session.tutorChatActionRan, outcome)
            XCTAssertEqual(session.reference?.notes.map(\.pitch), before, outcome)
        }
        XCTAssertNil(session.tutor)
    }

    // MARK: playNotes

    @MainActor func testPlayNotesRefusesNotesOffTheKeyboardOrTooMany() throws {
        let session = try player()
        let before = session.reference?.notes.map(\.pitch)
        let refused: [TutorChatAction] = [
            .init(kind: .playNotes, notes: ["C4", "C7"]),
            .init(kind: .playNotes, notes: ["B1"]),
            .init(kind: .playNotes, notes: ["C4+E4+G9"]),
            .init(kind: .playNotes, notes: ["middle C"]),
            .init(kind: .playNotes, notes: []),
            .init(kind: .playNotes),
            .init(kind: .playNotes, notes: Array(repeating: "C4", count: 33)),
            .init(kind: .playNotes, notes: Array(repeating: "C4+E4", count: 17)),
            .init(kind: .playNotes, notes: ["C4"], tempoBPM: 500),
        ]
        for action in refused {
            let outcome = session.applyTutorChatAction(action)
            XCTAssertFalse(session.tutorChatActionRan, outcome)
            XCTAssertFalse(session.isAuditioning, outcome)
        }
        XCTAssertTrue(session.applyTutorChatAction(refused[0]).contains("C7"))
        XCTAssertEqual(session.reference?.notes.map(\.pitch), before)
    }

    @MainActor func testPlayNotesLightsTheKeysAndKeepsThePiece() async throws {
        let session = try player()
        let before = session.reference?.notes.map(\.pitch)
        let outcome = session.applyTutorChatAction(.init(kind: .playNotes, notes: ["C2", "C4+E4+G4", "C6"], tempoBPM: 200))
        try XCTSkipUnless(session.isAuditioning, "No piano audio output is available: \(outcome)")
        XCTAssertTrue(session.tutorChatActionRan)
        XCTAssertEqual(session.reference?.notes.map(\.pitch), before)
        var lit = Set<Int>()
        for _ in 0..<300 where session.isAuditioning {
            lit.formUnion(session.auditionHeld)
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(lit.isSuperset(of: [64, 67]), "lit \(lit)")
        XCTAssertFalse(session.isAuditioning)
        XCTAssertEqual(session.reference?.notes.map(\.pitch), before)
    }

    @MainActor func testPlanPlaysNotesThenStartsTheExerciseWithoutAskingTheModelAgain() async throws {
        let session = try player()
        try XCTSkipUnless(session.auditionNotes([[60]], bpm: 200), "No piano audio output is available")
        session.stopAudition()
        let fake = DemoChat()
        fake.replies = [.init(onTopic: true, reply: "Listen to the C major arpeggio, then you try.", actions: [
            .init(kind: .playNotes, notes: ["C4", "E4", "G4", "C5"], tempoBPM: 200),
            .init(kind: .practiceExercise, hand: .right, mode: .wait, exercise: "arpeggio", key: "C", octaves: 1),
        ], suggestions: ["Now hands together"])]
        session.tutorChatClient = fake
        session.sendTutorChat("Play a C major arpeggio, then let me try")
        await settle(session)
        XCTAssertTrue(session.isAuditioning)
        XCTAssertEqual(session.tutorChatQueuedActions.map(\.kind), [.practiceExercise])
        XCTAssertEqual(session.score?.title, "Eight bars")
        await waitForDemo(session)
        XCTAssertTrue(session.tutorChatQueuedActions.isEmpty)
        XCTAssertEqual(session.score?.title, "C major arpeggio, 1 octave, right hand")
        XCTAssertEqual(session.reference?.notes.map(\.pitch), [60, 64, 67, 72, 67, 64, 60])
        XCTAssertNotNil(session.tutorAttempt)
        XCTAssertEqual(fake.calls.count, 1)
        XCTAssertTrue(session.tutorChat.turns.contains { $0.role == .app && $0.text.contains("Playing C4 E4 G4 C5") })
        XCTAssertTrue(session.tutorChat.turns.contains { $0.role == .app && $0.text.contains("Started C major arpeggio") })
        session.pauseTutorChatCoaching(); session.endTutoring()
    }

    // MARK: highlight

    @MainActor func testHighlightShowsRealBarsAndKeysOnly() throws {
        let session = try player()
        var outcome = session.applyTutorChatAction(.init(kind: .highlight, bars: [3, 4], keys: ["F4", "Bb3"]))
        XCTAssertTrue(session.tutorChatActionRan, outcome)
        XCTAssertEqual(session.tutorChatHighlightBars, [3, 4])
        XCTAssertEqual(session.tutorChatHighlightKeys, [65, 58])
        session.showTutorChatHighlight(bars: [], keys: [])
        for action in [TutorChatAction(kind: .highlight, bars: [99]),
                       .init(kind: .highlight, keys: ["C7"]),
                       .init(kind: .highlight, keys: ["X4"]),
                       .init(kind: .highlight)] {
            outcome = session.applyTutorChatAction(action)
            XCTAssertFalse(session.tutorChatActionRan, outcome)
            XCTAssertTrue(session.tutorChatHighlightBars.isEmpty && session.tutorChatHighlightKeys.isEmpty, outcome)
        }
    }

    @MainActor func testHighlightClearsItself() async throws {
        let session = try player()
        _ = session.applyTutorChatAction(.init(kind: .highlight, keys: ["C4"]))
        XCTAssertEqual(session.tutorChatHighlightKeys, [60])
        try await Task.sleep(nanoseconds: UInt64((PlaySession.tutorChatHighlightSeconds + 0.3) * 1_000_000_000))
        XCTAssertTrue(session.tutorChatHighlightKeys.isEmpty)
    }

    // MARK: Courses

    @MainActor func testEarTrainingAndSightReadingOpenTheirCourses() throws {
        let session = try player()
        XCTAssertFalse(session.applyTutorChatAction(.init(kind: .startEarTraining, level: 999)).isEmpty)
        XCTAssertFalse(session.tutorChatActionRan)

        var outcome = session.applyTutorChatAction(.init(kind: .startEarTraining, level: 1))
        XCTAssertTrue(session.tutorChatActionRan, outcome)
        XCTAssertEqual(session.lessonRunner.course, .ear)
        XCTAssertTrue(session.lessonRunner.page?.title.hasPrefix("Level 1 ·") == true)
        XCTAssertEqual(session.tab, .learn)

        outcome = session.applyTutorChatAction(.init(kind: .startSightReading))
        XCTAssertTrue(session.tutorChatActionRan, outcome)
        XCTAssertEqual(session.lessonRunner.course, .sight)
        XCTAssertNotNil(session.lessonRunner.page.flatMap { SightReadingCourse.unit.page($0.id) })
        XCTAssertTrue(TutorChatAction(kind: .startSightReading).endsPlan)
    }

    @MainActor func testContextListsTheCourses() throws {
        let session = try player()
        XCTAssertTrue(session.tutorChatContext(for: "Quiz me on intervals").availableLessons.contains("ear training levels 1–"))
    }

    // MARK: Schema

    func testSchemaCarriesTheNewFieldsAndRepliesDecode() throws {
        let text = String(describing: ModelTutorChatClient.schema)
        for field in ["exercise", "key", "octaves", "notes", "tempoBPM", "bars", "keys", "level",
                      "practiceExercise", "playNotes", "highlight", "startEarTraining", "startSightReading", "harmonicMinorScale"] {
            XCTAssertTrue(text.contains("\"\(field)\""), field)
        }
        let reply = #"{"on_topic":true,"reply":"Hear it, then play it.","actions":[{"kind":"playNotes","fromBar":null,"toBar":null,"hand":null,"tempoPercent":null,"mode":null,"lessonID":null,"goal":null,"exercise":null,"key":null,"octaves":null,"notes":["C4","E4+G4"],"tempoBPM":90,"bars":null,"keys":null,"level":null},{"kind":"practiceExercise","fromBar":null,"toBar":null,"hand":"LR","tempoPercent":60,"mode":"wait","lessonID":null,"goal":null,"exercise":"majorScale","key":"G","octaves":2,"notes":null,"tempoBPM":null,"bars":null,"keys":null,"level":null}],"suggestions":[]}"#
        let decoded = try JSONDecoder().decode(TutorChatReply.self, from: Data(reply.utf8))
        XCTAssertEqual(decoded.actions.map(\.kind), [.playNotes, .practiceExercise])
        XCTAssertEqual(decoded.actions[0].notes, ["C4", "E4+G4"])
        XCTAssertEqual(decoded.actions[1].octaves, 2)
        XCTAssertTrue(decoded.actions.allSatisfy(\.waitsForPlayer))
        XCTAssertEqual(decoded.actions[1].summary, "Practise G major scale, 60%")
        XCTAssertTrue(TutorChatInstructions.musicOnly.contains("practiceExercise"))
    }
}
#endif
