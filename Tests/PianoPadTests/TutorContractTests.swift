#if os(macOS)
import XCTest
import PianoAI
import PianoLessons
@testable import PianoPad

/// `docs/tutor_contract.json` is what `scripts/evaluate_tutor.py` sends the model: the
/// instructions and the reply schema, exactly as the app sends them. This test fails when the
/// file is out of date; regenerate it with
/// `UPDATE_TUTOR_CONTRACT=1 swift test --filter TutorContractTests`.
final class TutorContractTests: XCTestCase {
    static var contractURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/tutor_contract.json")
    }

    static func contract() throws -> Data {
        let contract: [String: Any] = [
            "instructions": ["adult": TutorChatInstructions.musicOnly, "child": TutorChatInstructions.child],
            "refusal": TutorChatInstructions.refusal,
            "schema": try JSONSerialization.jsonObject(with: JSONValue.object(["name": "tutor_chat", "schema": ModelTutorChatClient.schema]).data()),
            "child": ["chips": TutorChildPrompts.chips.map { ["chip": $0, "question": TutorChildPrompts.question(for: $0)] },
                      "actions": TutorChildPrompts.actions.map(\.rawValue).sorted()],
            "limits": ["actions": TutorChatReply.actionLimit, "suggestions": TutorChatReply.suggestionLimit,
                       "suggestionLength": TutorChatReply.suggestionLength],
            "appGuide": TutorAppGuide.text,
        ]
        return try JSONSerialization.data(withJSONObject: contract, options: [.prettyPrinted, .sortedKeys]) + Data("\n".utf8)
    }

    func testEvalContractMatchesTheApp() throws {
        let current = try Self.contract()
        if ProcessInfo.processInfo.environment["UPDATE_TUTOR_CONTRACT"] == "1" {
            try current.write(to: Self.contractURL, options: .atomic)
            return
        }
        let saved = try? Data(contentsOf: Self.contractURL)
        XCTAssertEqual(saved, current, "docs/tutor_contract.json is out of date: run UPDATE_TUTOR_CONTRACT=1 swift test --filter TutorContractTests")
    }
}
#endif
