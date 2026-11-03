#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import PianoPad

final class TutorChatComposerTests: XCTestCase {
    @MainActor func testReturnCanSendSuccessiveQuestionsWithoutReplacingTheEditor() throws {
        var draft = "First question"
        var focused = false
        var height: CGFloat = 34
        var sent: [String] = []
        let composer = TutorChatComposer(text: Binding(get: { draft }, set: { draft = $0 }),
                                         focused: Binding(get: { focused }, set: { focused = $0 }),
                                         height: Binding(get: { height }, set: { height = $0 }),
                                         send: { sent.append(draft); draft = "" })
        let coordinator = composer.makeCoordinator()
        let editor = TutorChatComposer.Editor()
        coordinator.editor = editor
        editor.delegate = coordinator
        for question in ["First question", "Follow-up question", "One more question"] {
            editor.string = question
            coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
            XCTAssertTrue(coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
            XCTAssertEqual(draft, "")
        }
        XCTAssertEqual(sent, ["First question", "Follow-up question", "One more question"])
    }

    @MainActor func testInputMethodAndLineBreakCommandsAreLeftToTheEditor() {
        var draft = ""
        var focused = false
        var height: CGFloat = 34
        var sends = 0
        let composer = TutorChatComposer(text: Binding(get: { draft }, set: { draft = $0 }),
                                         focused: Binding(get: { focused }, set: { focused = $0 }),
                                         height: Binding(get: { height }, set: { height = $0 }),
                                         send: { sends += 1 })
        let coordinator = composer.makeCoordinator()
        let editor = TutorChatComposer.Editor()
        XCTAssertFalse(coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertLineBreak(_:))))
        editor.setMarkedText("あ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(coordinator.textView(editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(sends, 0)
    }
}
#endif
