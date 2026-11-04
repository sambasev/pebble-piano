#if os(macOS)
import XCTest
import PianoAI
import PianoGraderCore
import PianoLessons
import PianoPadState
@testable import PianoPad

/// C6: a child taps fixed questions; the tutor may only demonstrate, show keys, slow down or stop.
private final class ChildChat: TutorChatClient, @unchecked Sendable {
    var replies: [TutorChatReply] = []
    var calls: [(context: TutorChatContext, question: String)] = []
    func reply(history: [TutorChatTurn], context: TutorChatContext, question: String) async throws -> TutorChatReply {
        calls.append((context, question))
        return replies.isEmpty ? TutorChatReply(onTopic: true, reply: "Nearly! Try C again.") : replies.removeFirst()
    }
}

final class TutorChatChildTests: XCTestCase {
    private var sandbox: AppDataSandbox!
    override func setUp() { sandbox = AppDataSandbox("ChatChild") }
    override func tearDown() { sandbox.remove() }

    @MainActor private func child() throws -> (PlaySession, ChildChat) {
        let session = sandbox.session()
        session.addLearner(name: "Kid", kind: .child)
        let notes = [60, 62, 64, 65].enumerated().map { i, pitch in
            NoteEvent(pitch: pitch, onset: Double(i) * 2, offset: Double(i) * 2 + 0.5,
                      onsetBeats: Double(i) * 4, offsetBeats: Double(i) * 4 + 1)
        }
        let file = sandbox.folder.appendingPathComponent("Four bars.mid")
        try MIDIFile.write(notes: notes).write(to: file)
        XCTAssertTrue(session.loadReference(file))
        let fake = ChildChat()
        session.tutorChatClient = fake
        session.makeTutorFeedbackClient = { throw ModelError.missingKey(.meta) }
        return (session, fake)
    }

    @MainActor private func settle(_ session: PlaySession) async {
        for _ in 0..<300 {
            try? await Task.sleep(nanoseconds: 5_000_000)
            if !session.tutorChatBusy { return }
        }
        XCTFail("Tutor did not settle")
    }

    @MainActor func testAChildCanOnlyTapTheFixedQuestions() async throws {
        let (session, fake) = try child()
        XCTAssertFalse(session.canChatWithTutor)
        XCTAssertTrue(session.canAskTutor)
        session.sendTutorChat("Tell me a joke")
        session.askTutorAsChild("Tell me a joke")
        await settle(session)
        XCTAssertTrue(fake.calls.isEmpty)

        session.askTutorAsChild(TutorChildPrompts.whatNote)
        await settle(session)
        XCTAssertEqual(fake.calls.count, 1)
        XCTAssertEqual(fake.calls[0].context.audience, .child)
        XCTAssertTrue(fake.calls[0].question.hasPrefix(TutorChildPrompts.whatNote))
        XCTAssertTrue(fake.calls[0].context.screen.contains("Keys expected now"))
        XCTAssertEqual(session.tutorChat.turns.map(\.text), [TutorChildPrompts.whatNote, "Nearly! Try C again."])
    }

    @MainActor func testOnlyChildActionsRun() async throws {
        let (session, fake) = try child()
        fake.replies = [.init(onTopic: true, reply: "Here it is!", actions: [
            .init(kind: .practicePassage, fromBar: 1, toBar: 2), .init(kind: .highlight, keys: ["C4"]),
            .init(kind: .openPiece, pieceRef: "#1"),
        ])]
        session.askTutorAsChild(TutorChildPrompts.whatNote)
        await settle(session)
        XCTAssertNil(session.tutor, "practicePassage isn't a child action")
        XCTAssertEqual(session.tutorChatHighlightKeys, [60])
        // The reply promised more than ran, so it's rewritten honestly.
        XCTAssertEqual(fake.calls.count, 2)
        XCTAssertTrue(fake.calls[1].question.contains("could not do what your last reply said"), fake.calls[1].question)
        XCTAssertEqual(session.tutorChat.turns.last { $0.role == .tutor }?.text, "Nearly! Try C again.")
        XCTAssertTrue(session.applyTutorChatAction(.init(kind: .switchInput, input: "computerKeyboard")).contains("adult learner"))
    }

    @MainActor func testTheGrownUpsQuestionIsAnsweredAsAnAdultWithoutActions() async throws {
        let (session, fake) = try child()
        fake.replies = [.init(onTopic: true, reply: "12 minutes this week.", actions: [.init(kind: .highlight, keys: ["C4"])])]
        session.askTutorAsChild(TutorChildPrompts.grownUps)
        await settle(session)
        XCTAssertEqual(fake.calls[0].context.audience, .grownUp)
        XCTAssertTrue(fake.calls[0].context.progress.contains("This week:"))
        XCTAssertTrue(session.tutorChatHighlightKeys.isEmpty)
    }

    func testEachAudienceGetsItsOwnInstructions() {
        func system(_ audience: TutorChatContext.Audience) -> String? {
            var context = TutorChatContext()
            context.audience = audience
            guard case .text(let text)? = ModelTutorChatClient.messages(history: [], context: context, question: "q").first?.parts.first
            else { return nil }
            return text
        }
        XCTAssertEqual(system(.child), TutorChatInstructions.child)
        XCTAssertEqual(system(.grownUp), TutorChatInstructions.musicOnly)
        XCTAssertEqual(system(.adult), TutorChatInstructions.musicOnly)
    }
}
#endif
