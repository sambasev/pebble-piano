#if os(macOS)
import XCTest
import PianoAI
import PianoCatalog
import PianoGraderCore
import PianoLessons
import PianoPadState
@testable import PianoPad

private final class LibraryChat: TutorChatClient, @unchecked Sendable {
    var replies: [TutorChatReply] = []
    var calls: [(TutorChatContext, String)] = []
    func reply(history: [TutorChatTurn], context: TutorChatContext, question: String) async throws -> TutorChatReply {
        calls.append((context, question))
        return replies.isEmpty ? TutorChatReply(onTopic: true, reply: "Here you go.") : replies.removeFirst()
    }
}

private actor FixedTransport: CatalogTransport {
    let data: Data
    init(data: Data) { self.data = data }
    func download(_ url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> Data { data }
}

final class TutorChatLibraryTests: XCTestCase {
    private var sandbox: AppDataSandbox!
    override func setUp() { sandbox = AppDataSandbox("ChatLibrary") }
    override func tearDown() { sandbox.remove() }

    @MainActor private func midi(_ name: String, pitches: [Int]) throws -> URL {
        let notes = pitches.enumerated().map { i, pitch in
            NoteEvent(pitch: pitch, onset: Double(i) * 2, offset: Double(i) * 2 + 0.5,
                      onsetBeats: Double(i) * 4, offsetBeats: Double(i) * 4 + 1)
        }
        let file = sandbox.folder.appendingPathComponent(name + ".mid")
        try MIDIFile.write(notes: notes).write(to: file)
        return file
    }

    @MainActor private func player(_ fake: LibraryChat) throws -> PlaySession {
        let session = sandbox.session()
        session.addLearner(name: "Adult", kind: .adult)
        XCTAssertTrue(session.loadReference(try midi("Eight bars", pitches: [60, 62, 64, 65, 67, 69, 71, 72])))
        session.tutorChatClient = fake
        return session
    }

    @MainActor private func settle(_ session: PlaySession) async {
        for _ in 0..<300 {
            try? await Task.sleep(nanoseconds: 5_000_000)
            if !session.tutorChatBusy { return }
        }
        XCTFail("Tutor did not settle")
    }

    @MainActor func testSearchAddsTopResultsWithStableIDsWithoutAnotherModelCall() async throws {
        let fake = LibraryChat()
        fake.replies = [.init(onTopic: true, reply: "Let me look.", actions: [.init(kind: .searchLibrary, query: "", composer: "Bach", difficulty: "Elementary")])]
        let session = try player(fake)
        session.sendTutorChat("Find me some easy Bach")
        await settle(session)
        XCTAssertEqual(fake.calls.count, 1, "searching needs no model call")
        let note = try XCTUnwrap(session.tutorChat.turns.last { $0.role == .app }?.text)
        XCTAssertTrue(note.contains("top"))
        let lines = note.split(separator: "\n").filter { $0.hasPrefix("#") }
        XCTAssertFalse(lines.isEmpty)
        XCTAssertLessThanOrEqual(lines.count, PlaySession.tutorLibraryResultLimit)
        for line in lines {
            XCTAssertTrue(line.contains("[catalog:mutopia-"), String(line))
            XCTAssertTrue(line.contains("Bach"), String(line))
            XCTAssertTrue(line.contains("Elementary"), String(line))
        }
        XCTAssertEqual(session.tutorChatLatestSearch.count, lines.count)
        // The same search gives the same IDs.
        let again = session.applyTutorChatAction(.init(kind: .searchLibrary, query: "", composer: "Bach", difficulty: "Elementary"))
        XCTAssertEqual(again.split(separator: "\n").filter { $0.hasPrefix("#") }, lines)
    }

    @MainActor func testSearchFindsRecentPiecesAndRejectsABadLevel() throws {
        let session = try player(LibraryChat())
        let outcome = session.applyTutorChatAction(.init(kind: .searchLibrary, query: "eight bars"))
        XCTAssertTrue(session.tutorChatActionRan)
        XCTAssertTrue(outcome.contains("#1 [recent:"), outcome)
        _ = session.applyTutorChatAction(.init(kind: .searchLibrary, query: "zzzz-no-such-piece"))
        XCTAssertFalse(session.tutorChatActionRan)
        _ = session.applyTutorChatAction(.init(kind: .searchLibrary, query: "", difficulty: "Grade 8"))
        XCTAssertFalse(session.tutorChatActionRan)
    }

    @MainActor func testOpeningAReturnedIDOpensItInPracticeAndKeepsTheConversation() async throws {
        let fake = LibraryChat()
        let session = try player(fake)
        let other = try midi("Second piece", pitches: [67, 65, 64])
        XCTAssertTrue(session.loadReference(other))
        XCTAssertTrue(session.loadReference(sandbox.folder.appendingPathComponent("Eight bars.mid")))
        session.sendTutorChat("What can I play?")
        await settle(session)
        let found = session.applyTutorChatAction(.init(kind: .searchLibrary, query: "Second piece"))
        let id = try XCTUnwrap(session.tutorChatLatestSearch.first)
        XCTAssertTrue(found.contains(id))
        session.tab = .musicLibrary
        let outcome = session.applyTutorChatAction(.init(kind: .openPiece, pieceRef: id))
        XCTAssertTrue(session.tutorChatActionRan, outcome)
        XCTAssertEqual(session.referenceURL?.standardizedFileURL, other.standardizedFileURL)
        XCTAssertEqual(session.tab, .practice)
        XCTAssertTrue(session.tutorChat.turns.contains { $0.text == "What can I play?" }, "opening from the chat keeps the conversation")
    }

    @MainActor func testUnknownOrFreeTextPieceIsRefused() throws {
        let session = try player(LibraryChat())
        let before = session.scoreID
        for ref in ["catalog:mutopia-61", "Ode to Joy", "#1", "", "goal:odeToJoy"] {
            let outcome = session.applyTutorChatAction(.init(kind: .openPiece, pieceRef: ref))
            XCTAssertFalse(session.tutorChatActionRan, ref)
            XCTAssertEqual(outcome, PlaySession.tutorUnknownPiece)
            _ = session.applyTutorChatAction(.init(kind: .previewPiece, pieceRef: ref))
            XCTAssertFalse(session.tutorChatActionRan, ref)
        }
        XCTAssertEqual(session.scoreID, before)
        // Found once, but past the latest search's results.
        _ = session.applyTutorChatAction(.init(kind: .searchLibrary, query: "Ode to Joy"))
        _ = session.applyTutorChatAction(.init(kind: .openPiece, pieceRef: "#5"))
        XCTAssertFalse(session.tutorChatActionRan)
        // A new conversation forgets what was found.
        session.resetTutorChat()
        _ = session.applyTutorChatAction(.init(kind: .openPiece, pieceRef: "goal:odeToJoy"))
        XCTAssertFalse(session.tutorChatActionRan)
        XCTAssertEqual(session.scoreID, before)
    }

    @MainActor func testPlanSearchesThenOpensTheFirstResult() async throws {
        let fake = LibraryChat()
        fake.replies = [.init(onTopic: true, reply: "Let's open Ode to Joy.", actions: [
            .init(kind: .searchLibrary, query: "Ode to Joy"),
            .init(kind: .openPiece, pieceRef: "#1"),
            .init(kind: .practicePassage, fromBar: 1, toBar: 1),
        ])]
        let session = try player(fake)
        session.sendTutorChat("Open Ode to Joy for me")
        await settle(session)
        XCTAssertEqual(fake.calls.count, 1)
        XCTAssertEqual(session.score?.title, "Ode to Joy")
        let notes = session.tutorChat.turns.filter { $0.role == .app }.map(\.text)
        XCTAssertTrue(notes.contains { $0.contains("#1 [goal:odeToJoy] Ode to Joy") }, "\(notes)")
        XCTAssertTrue(notes.contains("Opened Ode to Joy in Practice."), "\(notes)")
        XCTAssertTrue(notes.contains(PlaySession.skippedSteps(1)), "opening a piece ends the plan")
        XCTAssertTrue(session.tutorChatQueuedActions.isEmpty)
        XCTAssertNil(session.tutorAttempt)
    }

    @MainActor func testCatalogResultOpensThroughTheValidatedDownload() async throws {
        let session = try player(LibraryChat())
        let data = MIDIFile.write(notes: [NoteEvent(pitch: 60, onset: 0, offset: 0.5, velocity: 80)])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(MusicCatalog.bundled().pieces[0])) as? [String: Any])
        object["sha256"] = CatalogCache.digest(data)
        let catalog = try MusicCatalog.decode(JSONSerialization.data(withJSONObject: ["sourceRevision": "test", "pieces": [object]]))
        let piece = try XCTUnwrap(catalog.pieces.first)
        session.musicLibrary = MusicLibraryModel(catalog: catalog, cache: CatalogCache(directory: sandbox.folder.appendingPathComponent("cache"), transport: FixedTransport(data: data)))
        _ = session.applyTutorChatAction(.init(kind: .searchLibrary, query: piece.title, composer: piece.composer))
        XCTAssertEqual(session.tutorChatLatestSearch.first, "catalog:" + piece.id)
        _ = session.applyTutorChatAction(.init(kind: .openPiece, pieceRef: "#1"))
        XCTAssertTrue(session.tutorChatActionRan)
        for _ in 0..<200 where session.score?.title != piece.title { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(session.score?.title, piece.title)
        XCTAssertEqual(session.tab, .practice)
        XCTAssertTrue(session.tutorChat.turns.contains { $0.text == "Opened \(piece.title) in Practice." })
    }

    @MainActor func testPreviewOnlyForLibraryPiecesAndBookPageNeedsABook() throws {
        let session = try player(LibraryChat())
        _ = session.applyTutorChatAction(.init(kind: .searchLibrary, query: "Ode to Joy"))
        let outcome = session.applyTutorChatAction(.init(kind: .previewPiece, pieceRef: "#1"))
        XCTAssertFalse(session.tutorChatActionRan)
        XCTAssertTrue(outcome.contains("Only Music Library pieces"))
        _ = session.applyTutorChatAction(.init(kind: .openBookPage, page: 3))
        XCTAssertFalse(session.tutorChatActionRan)
        XCTAssertEqual(session.tab, .practice)
    }

    @MainActor func testContextHasALibrarySectionWithLevelsAndTheLibraryTabsSelection() throws {
        let session = try player(LibraryChat())
        var context = session.tutorChatContext(for: "Something easier?")
        XCTAssertTrue(context.library.contains("Elementary"))
        XCTAssertTrue(context.library.contains("Suggested level for this learner: Elementary"))
        XCTAssertTrue(context.library.contains("Recent pieces: "))
        XCTAssertTrue(context.prompt.contains("Library:\n"))
        XCTAssertFalse(context.library.contains("Selected:"))
        session.musicLibrary.difficulty = .intermediate
        session.tab = .musicLibrary
        context = session.tutorChatContext(for: "Something easier than this?")
        XCTAssertTrue(context.library.contains("Music Library tab filters: Intermediate"))
        XCTAssertTrue(context.library.contains("Selected: "))
        XCTAssertTrue(context.library.contains(", Intermediate"))
    }

    func testSchemaListsLibraryFieldsAsRequired() {
        guard case .object(let root) = ModelTutorChatClient.schema, case .object(let props)? = root["properties"],
              case .object(let actions)? = props["actions"], case .object(let item)? = actions["items"],
              case .array(let required)? = item["required"] else { return XCTFail("schema shape") }
        for field in ["query", "composer", "difficulty", "pieceRef", "page", "fromBar", "kind"] {
            XCTAssertTrue(required.contains(.string(field)), field)
        }
        XCTAssertTrue(TutorChatAction.Kind.allCases.contains(.searchLibrary))
        XCTAssertFalse(TutorChatAction(kind: .searchLibrary).waitsForPlayer)
        XCTAssertFalse(TutorChatAction(kind: .searchLibrary).endsPlan)
        XCTAssertTrue(TutorChatAction(kind: .openPiece).endsPlan)
    }
}
#endif
