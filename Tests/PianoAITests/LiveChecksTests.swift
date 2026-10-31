import XCTest
@testable import PianoAI

/// Calls the real Meta Model API. Skipped unless a key is available, either saved in the
/// Keychain from AI settings or exported:
///
///     PIANOAI_LIVE=1 MODEL_API_KEY=… swift test --filter LiveChecksTests
final class LiveChecksTests: XCTestCase {
    func testMetaChecks() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PIANOAI_LIVE"] == "1", "set PIANOAI_LIVE=1 to call the API")
        let client = try ModelClient.configured(.meta)
        let results = await AIChecks.run(client)
        for r in results { print(r.passed ? "✓" : "✗", r.name, String(format: "%.1fs", r.seconds), r.detail) }
        XCTAssertTrue(results.allSatisfy(\.passed))
    }
}
