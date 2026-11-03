#if os(macOS)
import XCTest
import PianoCatalog
import PianoGraderCore
import PianoPadState
@testable import PianoPad

private actor LibraryTransport: CatalogTransport {
    let data: Data
    let delayed: Bool
    let failure: Bool
    init(data: Data, delayed: Bool = false, failure: Bool = false) {
        self.data = data; self.delayed = delayed; self.failure = failure
    }
    func download(_ url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> Data {
        progress(0.5)
        if delayed { try await Task.sleep(nanoseconds: 10_000_000_000) }
        if failure { throw URLError(.notConnectedToInternet) }
        return data
    }
}

@MainActor
final class MusicLibraryTests: XCTestCase {
    var directory: URL!
    var sandbox: AppDataSandbox!
    override func setUpWithError() throws {
        sandbox = AppDataSandbox("MusicLibrary")
        directory = sandbox.folder
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { sandbox.remove() }
    func player() throws -> PlaySession {
        if sandbox.store.learners.isEmpty { try sandbox.store.add(name: "Catalog test", kind: .adult) }
        let player = sandbox.session()
        player.needsLearnerPick = false
        return player
    }
    func fixture() throws -> (CatalogPiece, Data, URL) {
        let midi = MIDIFile.write(notes: [NoteEvent(pitch: 60, onset: 0, offset: 0.5, velocity: 80)])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(MusicCatalog.bundled().pieces[0])) as? [String: Any])
        object["sha256"] = CatalogCache.digest(midi)
        let piece = try JSONDecoder().decode(CatalogPiece.self, from: JSONSerialization.data(withJSONObject: object))
        let url = directory.appendingPathComponent("piece.mid")
        try midi.write(to: url)
        return (piece, midi, url)
    }

    func testStartLearningSurvivesDeferredTabChangesAndFreePracticeEndsTutor() async throws {
        let player = try player(), (piece, _, url) = try fixture()
        player.tab = .musicLibrary
        XCTAssertTrue(player.openCatalogPiece(url, piece: piece, tutored: true))
        XCTAssertEqual(player.tab, .practice)
        XCTAssertNotNil(player.tutor)
        XCTAssertEqual(player.score?.title, piece.title)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNotNil(player.tutor, "A stale tab callback must not end the new tutor")
        XCTAssertTrue(player.openCatalogPiece(url, piece: piece, tutored: false))
        XCTAssertNil(player.tutor)
    }

    func testInvalidEditionPreservesReferenceTutorAndTab() throws {
        let player = try player(), (piece, _, url) = try fixture()
        XCTAssertTrue(player.openCatalogPiece(url, piece: piece, tutored: true))
        let before = player.currentPieceID
        let score = player.scoreID
        let bad = directory.appendingPathComponent("bad.mid")
        try Data("invalid".utf8).write(to: bad)
        XCTAssertFalse(player.openCatalogPiece(bad, piece: piece, tutored: false))
        XCTAssertEqual(player.currentPieceID, before)
        XCTAssertEqual(player.scoreID, score)
        XCTAssertNotNil(player.tutor)
        XCTAssertEqual(player.referenceURL, url)
    }

    func testReopeningHasOneRecentEntryAndSameSavedHistory() throws {
        let player = try player(), (piece, midi, url) = try fixture()
        XCTAssertTrue(player.openCatalogPiece(url, piece: piece, tutored: false))
        let id = try XCTUnwrap(player.currentPieceID)
        let learner = try XCTUnwrap(player.learner)
        let history = player.learnerStore.history(for: learner.id)
        try history.record(piece: id, midi: midi, report: Data("{}".utf8), score: 1, passed: true)
        XCTAssertTrue(player.openCatalogPiece(url, piece: piece, tutored: false))
        XCTAssertEqual(player.currentPieceID, id)
        XCTAssertEqual(player.learnerSettings.recentPieces.count, 1)
        XCTAssertEqual(history.progress(for: id)?.attempts, 1)
        XCTAssertEqual(history.takes(for: id).count, 1)
    }

    func testDownloadFilterAndBrowsingStateSurviveOpening() async throws {
        let (piece, midi, _) = try fixture()
        let cache = CatalogCache(directory: directory.appendingPathComponent("cache"), transport: LibraryTransport(data: midi))
        let model = MusicLibraryModel(cache: cache)
        model.query = "Bach"; model.composer = "J. S. Bach"; model.selectedID = "mutopia-61"
        model.downloadedOnly = true
        XCTAssertTrue(model.filtered.isEmpty)
        model.open(piece) { _ in true }
        for _ in 0..<100 where model.downloadingID != nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(model.downloaded.contains(piece.id))
        XCTAssertEqual(model.query, "Bach")
        XCTAssertEqual(model.composer, "J. S. Bach")
        XCTAssertEqual(model.selectedID, "mutopia-61")
        XCTAssertTrue(model.downloadedOnly)
    }

    func testCancelledDownloadNeverOpensAndFailureCanRetry() async throws {
        let (piece, midi, _) = try fixture()
        let slow = MusicLibraryModel(cache: CatalogCache(directory: directory.appendingPathComponent("slow"), transport: LibraryTransport(data: midi, delayed: true)))
        var opened = false
        slow.open(piece) { _ in opened = true; return true }
        slow.cancel()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(opened); XCTAssertNil(slow.downloadingID); XCTAssertNil(slow.error)
        let failure = MusicLibraryModel(cache: CatalogCache(directory: directory.appendingPathComponent("failure"), transport: LibraryTransport(data: midi, failure: true)))
        failure.open(piece) { _ in opened = true; return true }
        for _ in 0..<100 where failure.downloadingID != nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNotNil(failure.error); XCTAssertFalse(opened)
        failure.open(piece) { _ in true }
        XCTAssertNil(failure.error, "Retry clears the earlier error")
        failure.cancel()
    }
}
#endif
