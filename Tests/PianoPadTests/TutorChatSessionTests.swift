#if os(macOS)
import XCTest
import PianoAI
import PianoLessons
import PianoPadState
@testable import PianoPad

private final class FakeChat: TutorChatClient, @unchecked Sendable {
    var reply = TutorChatReply(onTopic: true, reply: "A whole note gets four beats.")
    var calls: [(history: [TutorChatTurn], context: TutorChatContext, question: String)] = []
    func reply(history: [TutorChatTurn], context: TutorChatContext, question: String) async throws -> TutorChatReply {
        calls.append((history, context, question))
        return reply
    }
}

final class TutorChatSessionTests: XCTestCase {
    var sandbox: AppDataSandbox!
    override func setUp() { sandbox = AppDataSandbox("TutorChat") }
    override func tearDown() { sandbox.remove() }

    @MainActor private func waitForAnswer(_ session: PlaySession) async {
        for _ in 0..<200 where session.tutorChatBusy { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    @MainActor func testAdultAsksAndGetsAnAnswer() async {
        let session = sandbox.session()
        session.addLearner(name: "Sam", kind: .adult)
        let fake = FakeChat()
        session.tutorChatClient = fake
        XCTAssertTrue(session.canChatWithTutor)
        session.sendTutorChat("How long is a whole note?")
        await waitForAnswer(session)
        XCTAssertEqual(fake.calls.count, 1)
        XCTAssertEqual(session.tutorChat.turns.last?.text, "A whole note gets four beats.")
    }

    @MainActor func testChildCanNeverChat() async {
        let session = sandbox.session()
        session.addLearner(name: "Kid", kind: .child)
        let fake = FakeChat()
        session.tutorChatClient = fake
        XCTAssertFalse(session.canChatWithTutor)
        session.sendTutorChat("How long is a whole note?")
        await waitForAnswer(session)
        XCTAssertTrue(fake.calls.isEmpty)
        XCTAssertTrue(session.tutorChat.turns.isEmpty)
    }

    @MainActor func testNoLearnerCannotChat() {
        let session = sandbox.session()
        XCTAssertFalse(session.canChatWithTutor)
    }

    @MainActor func testSwitchingLearnerClearsTheChat() async {
        let session = sandbox.session()
        session.addLearner(name: "Sam", kind: .adult)
        session.tutorChatClient = FakeChat()
        session.sendTutorChat("What is a chord?")
        await waitForAnswer(session)
        XCTAssertFalse(session.tutorChat.turns.isEmpty)
        session.addLearner(name: "Kid", kind: .child)
        XCTAssertTrue(session.tutorChat.turns.isEmpty)
    }

    @MainActor func testANewPieceStartsANewChat() async throws {
        let session = sandbox.session()
        session.addLearner(name: "Sam", kind: .adult)
        session.tutorChatClient = FakeChat()
        session.sendTutorChat("What is a chord?")
        await waitForAnswer(session)
        XCTAssertFalse(session.tutorChat.turns.isEmpty)
        let piece = try XCTUnwrap(PlaySession.bundledResource("Examples/five-finger.mid"))
        session.loadReference(piece, remember: false)
        XCTAssertTrue(session.tutorChat.turns.isEmpty)
    }

    @MainActor func testOffTopicIsRefusedAndNotSentBack() async {
        let session = sandbox.session()
        session.addLearner(name: "Sam", kind: .adult)
        let fake = FakeChat()
        fake.reply = TutorChatReply(onTopic: false, reply: "")
        session.tutorChatClient = fake
        session.sendTutorChat("What's the weather?")
        await waitForAnswer(session)
        XCTAssertEqual(session.tutorChat.turns.last?.text, TutorChatInstructions.refusal)
        fake.reply = TutorChatReply(onTopic: true, reply: "C, E and G.")
        session.sendTutorChat("What notes are in a C chord?")
        await waitForAnswer(session)
        XCTAssertEqual(fake.calls.last?.history, [])
    }

    @MainActor func testNoKeyLeavesANote() {
        let session = sandbox.session()
        session.addLearner(name: "Sam", kind: .adult)
        session.makeTutorChatClient = { throw ModelError.missingKey(.meta) }
        session.sendTutorChat("What is a chord?")
        XCTAssertNotNil(session.tutorChatNote)
        XCTAssertTrue(session.tutorChat.turns.isEmpty)
    }

    // MARK: Muse Spark adapter

    func testModelClientSendsSchemaContextAndPicture() async throws {
        let endpoint = ModelEndpoint(provider: .meta, baseURL: URL(string: "https://api.meta.ai/v1")!, apiKey: "test")
        let client = ModelClient(endpoint: endpoint, log: UsageLog(printsToConsole: false), transport: { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let format = body["response_format"] as? [String: Any]
            XCTAssertEqual((format?["json_schema"] as? [String: Any])?["name"] as? String, "tutor_chat")
            let messages = body["messages"] as! [[String: Any]]
            XCTAssertTrue((messages[0]["content"] as! String).contains("only talk about music"))
            XCTAssertEqual(messages[1]["role"] as? String, "user")
            XCTAssertEqual(messages[2]["role"] as? String, "assistant")
            let last = messages[3]["content"] as! [[String: Any]]
            XCTAssertTrue((last[0]["text"] as! String).contains("<context>"))
            XCTAssertEqual(last[1]["type"] as? String, "image_url")
            let reply = #"{"on_topic":true,"reply":"Bar 2 is staccato."}"#
            let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": reply]]]])
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let history = [TutorChatTurn(role: .learner, text: "Hi"), TutorChatTurn(role: .tutor, text: "Hello")]
        let context = TutorChatContext(bookTitle: "Starter", currentPage: 2, pages: [], pageImage: Data([0xFF]))
        let reply = try await ModelTutorChatClient(client: client, model: "m").reply(history: history, context: context, question: "Bar 2?")
        XCTAssertEqual(reply, TutorChatReply(onTopic: true, reply: "Bar 2 is staccato."))
    }

    func testUnreadableModelReplyCountsAsOffTopic() async throws {
        let endpoint = ModelEndpoint(provider: .meta, baseURL: URL(string: "https://api.meta.ai/v1")!, apiKey: "test")
        let client = ModelClient(endpoint: endpoint, log: UsageLog(printsToConsole: false), transport: { request in
            (Data(#"{"choices":[{"message":{"content":"Sure! Here's the weather."}}]}"#.utf8),
             HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let reply = try await ModelTutorChatClient(client: client, model: "m").reply(history: [], context: .init(), question: "Weather?")
        XCTAssertFalse(reply.onTopic)
    }
}
#endif
