import XCTest
@testable import PianoLessons

private final class StubTutorHTTP: URLProtocol {
    static var status = 200
    static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class TutorFeedbackTests: XCTestCase {
    func testResponseAndFailures() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubTutorHTTP.self]
        let client = MetaTutorFeedbackClient(key: "test", session: URLSession(configuration: config))
        StubTutorHTTP.body = Data(#"{"output":[{"type":"reasoning"},{"type":"message","content":[{"type":"output_text","text":"Practise bar 3 slowly."}]}]}"#.utf8)
        let text = try await client.explain(context: "Bar 3", question: "Why?")
        XCTAssertEqual(text, "Practise bar 3 slowly.")
        for status in [401, 429, 500] {
            StubTutorHTTP.status = status
            do { _ = try await client.explain(context: "", question: ""); XCTFail("Expected HTTP failure") } catch {}
        }
        StubTutorHTTP.status = 200
        StubTutorHTTP.body = Data("{}".utf8)
        do { _ = try await client.explain(context: "", question: ""); XCTFail("Expected invalid response") } catch {}
    }
}
