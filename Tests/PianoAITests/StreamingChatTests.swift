import XCTest
@testable import PianoAI

final class StreamingChatTests: XCTestCase {
    let endpoint = ModelEndpoint(provider: .meta, baseURL: URL(string: "https://api.meta.ai/v1")!, apiKey: "test-key")

    static func sse(_ events: [JSONValue]) throws -> String {
        try events.map { "data: \(String(decoding: try $0.data(), as: UTF8.self))\n\n" }.joined() + "data: [DONE]\n\n"
    }

    func testStreamedChatJoinsDeltasAndReadsUsage() async throws {
        let body = try Self.sse([
            ["model": "muse-wonder-1.0", "choices": [["delta": ["role": "assistant"]]]],
            ["choices": [["delta": ["content": "{\"notes\":"]]]],
            ["choices": [["delta": ["content": "[\"C\"]}"]]]],
            ["choices": [], "usage": ["prompt_tokens": 40, "completion_tokens": 900]],
        ])
        let fake = FakeTransport([(200, body)])
        let client = ModelClient(endpoint: endpoint, log: UsageLog(printsToConsole: false), transport: fake.transport)
        let r = try await client.chat([.user("hi")], options: .init(model: MetaModels.wonder, stream: true))
        XCTAssertEqual(r.text, "{\"notes\":[\"C\"]}")
        XCTAssertEqual(r.model, "muse-wonder-1.0")
        XCTAssertEqual(r.inputTokens, 40)
        XCTAssertEqual(r.outputTokens, 900)

        let req = fake.requests[0]
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        let sent = try JSONValue(parsing: req.httpBody ?? Data())
        XCTAssertEqual(sent["stream"], true)
        XCTAssertEqual(sent["stream_options"]?["include_usage"], true)
    }

    func testStreamErrorThrows() async {
        let fake = FakeTransport([(200, "data: {\"error\":{\"message\":\"overloaded\"}}\n\n")])
        let client = ModelClient(endpoint: endpoint, log: UsageLog(printsToConsole: false), transport: fake.transport)
        do {
            _ = try await client.chat([.user("hi")], options: .init(stream: true))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ModelError, .streamError("overloaded"))
        }
    }

    func testNonStreamedRequestHasNoStreamField() async throws {
        let fake = FakeTransport([(200, #"{"choices":[{"message":{"content":"ok"}}]}"#)])
        let client = ModelClient(endpoint: endpoint, log: UsageLog(printsToConsole: false), transport: fake.transport)
        _ = try await client.chat([.user("hi")])
        let sent = try JSONValue(parsing: fake.requests[0].httpBody ?? Data())
        XCTAssertNil(sent["stream"])
    }
}
