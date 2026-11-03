import XCTest
@testable import PianoLessons

final class TutorChatMemoryTests: XCTestCase {
    private var folder: URL!
    override func setUp() { folder = FileManager.default.temporaryDirectory.appendingPathComponent("TutorMemory-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func turns() -> [TutorChatTurn] {
        [.init(role: .learner, text: "How do I count bar 2?"),
         .init(role: .tutor, text: "Count 1-and-2.", suggestions: ["Play it for me"]),
         .init(role: .learner, text: "Write code", refused: true)]
    }

    func testConversationRestoresOnlyForTheSamePieceWhileRecent() throws {
        let memory = TutorChatMemory(folder: folder)
        XCTAssertNil(memory.chat(for: "file:abc"))
        let now = Date(), saved = turns()
        try memory.save(piece: "file:abc", turns: saved, now: now)
        let restored = try XCTUnwrap(memory.chat(for: "file:abc", now: now))
        XCTAssertEqual(restored, saved)
        XCTAssertEqual(restored[1].suggestions, ["Play it for me"])
        XCTAssertNil(memory.chat(for: "file:other", now: now))
        XCTAssertNil(memory.chat(for: "file:abc", now: now.addingTimeInterval(TutorChatMemory.restoreWithin + 1)))
        try memory.save(piece: nil, turns: [], now: now)
        XCTAssertNil(memory.chat(for: nil, now: now))
    }

    func testNotesAreCappedTrimmedAndOnlyTheLatestArePrompted() throws {
        let memory = TutorChatMemory(folder: folder)
        let day = Date(timeIntervalSince1970: 1_793_000_000)
        for i in 0..<(TutorChatMemory.noteLimit + 5) {
            try memory.add(.init(date: day, piece: "Ode to Joy", text: "  Note \(i)  "))
        }
        try memory.add(.init(date: day, piece: "Empty", text: "   "))
        let notes = memory.notes()
        XCTAssertEqual(notes.count, TutorChatMemory.noteLimit)
        XCTAssertEqual(notes.last?.text, "Note 24")
        let prompt = TutorChatMemory.prompt(notes)
        XCTAssertEqual(prompt.split(separator: "\n").count, TutorChatMemory.promptNotes)
        XCTAssertTrue(prompt.contains("Ode to Joy: Note 24"))
        XCTAssertFalse(prompt.contains("Note 21"))
    }

    func testOnlyAnsweredConversationsAreNotedAndTheFallbackListsQuestions() {
        XCTAssertTrue(TutorChatMemory.isWorthNoting(turns()))
        XCTAssertFalse(TutorChatMemory.isWorthNoting([.init(role: .learner, text: "Hi")]))
        XCTAssertFalse(TutorChatMemory.isWorthNoting([.init(role: .app, text: "Started bar 2")]))
        XCTAssertEqual(TutorChatMemory.fallbackNote(turns()), "Asked: How do I count bar 2?")
    }

    func testOlderSavedTurnsWithoutSuggestionsStillDecode() throws {
        let json = #"{"id":"9F2D8E1A-0000-4000-8000-000000000001","role":"tutor","text":"Hi"}"#
        let turn = try JSONDecoder().decode(TutorChatTurn.self, from: Data(json.utf8))
        XCTAssertFalse(turn.refused)
        XCTAssertEqual(turn.suggestions, [])
    }
}
