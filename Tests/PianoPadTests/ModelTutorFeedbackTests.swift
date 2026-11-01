#if os(macOS)
import XCTest
import PianoAI
import PianoLessons
@testable import PianoPad

final class ModelTutorFeedbackTests: XCTestCase {
    let endpoint = ModelEndpoint(provider: .meta, baseURL: URL(string: "https://api.meta.ai/v1")!, apiKey: "test")

    func testSharedTransportAndUsageLog() async throws {
        let log = UsageLog(printsToConsole: false)
        let client = ModelClient(endpoint: endpoint, log: log, transport: { request in
            XCTAssertEqual(request.timeoutInterval, 20)
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, "tutor-model")
            let messages = body["messages"] as! [[String: Any]]
            XCTAssertTrue((messages[0]["content"] as! String).contains("piano teacher"))
            XCTAssertTrue((messages[1]["content"] as! String).contains("bar 3"))
            let data = Data(#"{"choices":[{"message":{"content":"Let's try bar 3 again slowly."}}],"usage":{"prompt_tokens":30,"completion_tokens":10}}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let adapter = ModelTutorFeedbackClient(client: client, model: "tutor-model")
        let result = try await adapter.explain(context: "bar 3 rushed", question: "What next?")
        XCTAssertEqual(result, "Let's try bar 3 again slowly.")
        let totals = await log.totals()
        XCTAssertEqual(totals.calls, 1); XCTAssertEqual(totals.inputTokens, 30); XCTAssertEqual(totals.outputTokens, 10)
    }
    func testFailuresAndEmptyReply() async {
        for status in [401, 429, 500, 200] {
            let client = ModelClient(endpoint: endpoint, log: UsageLog(printsToConsole: false), transport: { request in
                (Data(#"{"choices":[{"message":{"content":" "}}]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            })
            do { _ = try await ModelTutorFeedbackClient(client: client, model: MetaModels.spark).explain(context: "", question: ""); XCTFail("Expected failure") } catch {}
        }
    }
    func testOneLiveTutorCallWhenEnabled() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PIANOAI_TUTOR_LIVE"] == "1", "Set PIANOAI_TUTOR_LIVE=1 for one real tutor request")
        try LegacyTutorKeyMigration.run()
        try XCTSkipIf(APIKeyStore.key(for: .meta) == nil, "No configured Meta key")
        let before = await UsageLog.shared.totals()
        let text = try await ModelTutorFeedbackClient.configured().explain(context: "The learner played D instead of E in bar 3. The deterministic planner selected note-by-note learning of bar 3. Timing was not assessed.", question: "Explain this like a piano teacher in two short sentences.")
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.lowercased().contains("bar") || text.contains("3"))
        let after = await UsageLog.shared.totals()
        XCTAssertEqual(after.calls, before.calls + 1)
        print("Tutor live response: \(text)")
    }
}
#endif
