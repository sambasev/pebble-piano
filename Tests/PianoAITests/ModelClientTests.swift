import XCTest
@testable import PianoAI

/// Records requests and plays back canned responses, so no test touches the network.
final class FakeTransport: @unchecked Sendable {
    var requests: [URLRequest] = []
    var responses: [(Int, Data)]

    init(_ responses: [(Int, String)]) { self.responses = responses.map { ($0.0, Data($0.1.utf8)) } }

    var transport: ModelClient.Transport {
        { request in
            self.requests.append(request)
            let (status, body) = self.responses.removeFirst()
            return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}

final class ModelClientTests: XCTestCase {
    let endpoint = ModelEndpoint(provider: .meta, baseURL: URL(string: "https://api.meta.ai/v1")!, apiKey: "test-key")

    func client(_ fake: FakeTransport) -> ModelClient {
        ModelClient(endpoint: endpoint, log: UsageLog(printsToConsole: false), transport: fake.transport)
    }

    func body(_ r: URLRequest) throws -> JSONValue { try JSONValue(parsing: r.httpBody ?? Data()) }

    func testChatRequestShapeAndStructuredReply() async throws {
        let fake = FakeTransport([(200, #"{"model":"muse-spark-1.3","choices":[{"message":{"role":"assistant","content":"{\"notes\":[\"C\",\"E\",\"G\"]}"}}],"usage":{"prompt_tokens":12,"completion_tokens":7}}"#)])
        let schema: JSONValue = ["type": "object"]
        let png = Data([0x89, 0x50])
        let r = try await client(fake).chat(
            [.system("sys"), .user([.text("look"), .image(png, mimeType: "image/png")])],
            options: .init(schema: ("Triad", schema), reasoningEffort: "low"))

        struct Reply: Decodable, Equatable { let notes: [String] }
        XCTAssertEqual(try r.decode(Reply.self), Reply(notes: ["C", "E", "G"]))
        XCTAssertEqual(r.inputTokens, 12)
        XCTAssertEqual(r.outputTokens, 7)

        let req = fake.requests[0]
        XCTAssertEqual(req.url?.absoluteString, "https://api.meta.ai/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let b = try body(req)
        XCTAssertEqual(b["model"], "muse-spark-1.3")
        XCTAssertEqual(b["reasoning_effort"], "low")
        XCTAssertEqual(b["response_format"]?["type"], "json_schema")
        XCTAssertEqual(b["response_format"]?["json_schema"]?["name"], "Triad")
        XCTAssertEqual(b["messages"]?[0]?["content"], "sys")
        XCTAssertEqual(b["messages"]?[1]?["content"]?[1]?["image_url"]?["url"]?.stringValue,
                       "data:image/png;base64,\(png.base64EncodedString())")
    }

    func testHTTPErrorCarriesServerMessage() async {
        let fake = FakeTransport([(401, #"{"error":{"message":"Invalid API key","type":"authentication_error"}}"#)])
        do {
            _ = try await client(fake).chat([.user("hi")])
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ModelError, .http(status: 401, message: "Invalid API key"))
        }
    }

    func testSegmentStreamsAndParses() async throws {
        let line = "<0f>0<|box;x1=1;y1=2;x2=3;y2=4;w=10;h=10|><|mask;x=0;y=0;data=1,1,~a|>"
        let delta = try JSONValue.object(["type": "response.output_text.delta", "delta": .string(line)]).data()
        let stream = "event: response.output_text.delta\ndata: \(String(decoding: delta, as: UTF8.self))\n\n"
            + "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"usage\":{\"input_tokens\":5,\"output_tokens\":9}}}\n\n"
        let fake = FakeTransport([(200, stream)])
        let segments = try await client(fake).segment(image: Data([1]), prompt: "music staff")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].box, .init(x1: 1, y1: 2, x2: 3, y2: 4))

        let req = fake.requests[0]
        XCTAssertEqual(req.url?.path, "/v1/responses")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        let b = try body(req)
        XCTAssertEqual(b["model"], "sam-3.1")
        XCTAssertEqual(b["stream"], true)
        XCTAssertEqual(b["input"]?[0]?["content"]?[0]?["text"], "music staff")
        XCTAssertEqual(b["input"]?[0]?["content"]?[1]?["type"], "input_image")
    }

    func testSegmentStreamErrorThrows() async {
        let fake = FakeTransport([(200, "data: {\"type\":\"error\",\"error\":{\"message\":\"bad image\"}}\n\n")])
        do {
            _ = try await client(fake).segment(image: Data([1]), prompt: "x")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? ModelError, .streamError("bad image"))
        }
    }

    func testZeroMatchesIsEmptyNotAnError() async throws {
        let fake = FakeTransport([(200, "data: {\"type\":\"response.completed\",\"response\":{}}\n\n")])
        let segments = try await client(fake).segment(image: Data([1]), prompt: "x")
        XCTAssertEqual(segments, [])
    }

    func testTranscribeSendsMultipartAndReadsTranscript() async throws {
        let fake = FakeTransport([(200, #"{"sessionId":"s1","transcript":"Why do I keep missing bar three?","audioDurationMs":2100,"turns":[]}"#)])
        let wav = WAV.encode(samples: [0, 1, -1], sampleRate: 24_000)
        let t = try await client(fake).transcribe(wav: wav, keywords: ["PianoPad"])
        XCTAssertEqual(t.text, "Why do I keep missing bar three?")
        XCTAssertEqual(t.audioMilliseconds, 2100)

        let req = fake.requests[0]
        XCTAssertEqual(req.url?.path, "/v1/asr/transcribe")
        let contentType = try XCTUnwrap(req.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let text = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"request\""))
        XCTAssertTrue(text.contains("\"mode\":\"PUSH_TO_TALK\""))
        XCTAssertTrue(text.contains("\"keywords\":[\"PianoPad\"]"))
        XCTAssertTrue(text.contains("name=\"audio\"; filename=\"audio.wav\""))
    }

    func testUsageIsLogged() async throws {
        let log = UsageLog(printsToConsole: false)
        let fake = FakeTransport([(200, #"{"choices":[{"message":{"content":"ok"}}],"usage":{"prompt_tokens":3,"completion_tokens":1}}"#), (500, "boom")])
        let c = ModelClient(endpoint: endpoint, log: log, transport: fake.transport)
        _ = try await c.chat([.user("hi")])
        _ = try? await c.chat([.user("hi")])
        let totals = await log.totals()
        XCTAssertEqual(totals.calls, 2)
        XCTAssertEqual(totals.failures, 1)
        XCTAssertEqual(totals.inputTokens, 3)
    }
}
