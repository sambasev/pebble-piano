import XCTest
@testable import PianoLessons

final class TutorChatStreamingTests: XCTestCase {
    func testTheReplyGrowsAsTheJSONArrives() {
        let full = #"{"on_topic": true, "reply": "Count \"1 and 2\":\nslowly é!", "actions": []}"#
        var shown: [String] = []
        for end in full.indices {
            if let text = TutorChatStreaming.partialReply(String(full[..<end])), shown.last != text { shown.append(text) }
        }
        XCTAssertEqual(shown.last, "Count \"1 and 2\":\nslowly é!")
        XCTAssertTrue(shown.allSatisfy { shown.last!.hasPrefix($0) }, "text only ever grows: \(shown)")
    }

    func testNothingShowsUntilTheAnswerIsOnTopic() {
        XCTAssertNil(TutorChatStreaming.partialReply(#"{"on_topic": fal"#))
        XCTAssertNil(TutorChatStreaming.partialReply(#"{"on_topic": false, "reply": "Here's the essay"#))
        XCTAssertNil(TutorChatStreaming.partialReply(#"{"reply": "Sure", "on_topic": true"#))
        XCTAssertEqual(TutorChatStreaming.partialReply(#"{"on_topic":true,"reply":""#), "")
        XCTAssertEqual(TutorChatStreaming.partialReply(#"{"on_topic":true,"reply":"Half \"#), "Half ")
        XCTAssertEqual(TutorChatStreaming.partialReply(#"{"on_topic":true,"reply":"A \u00"#), "A ")
    }
}
