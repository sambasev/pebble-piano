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

    private func waitForDownload(_ model: MusicLibraryModel) async throws {
        for _ in 0..<100 where model.downloadingID != nil { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNil(model.downloadingID)
    }

    func testPreviewToggleNaturalFinishAndOfflineReopen() async throws {
        let (piece, midi, _) = try fixture()
        let cache = CatalogCache(directory: directory.appendingPathComponent("preview"), transport: LibraryTransport(data: midi))
        let model = MusicLibraryModel(cache: cache)
        model.query = "Bach"; model.selectedID = "mutopia-61"
        var starts = 0, stops = 0
        var finish: (() -> Void)?
        let play: (URL, @escaping () -> Void) -> Bool = { url, ended in
            XCTAssertEqual(try? Data(contentsOf: url), midi)
            starts += 1; finish = ended
            return true
        }
        model.preview(piece, play: play, stop: { stops += 1 })
        try await waitForDownload(model)
        XCTAssertEqual(starts, 1); XCTAssertEqual(model.previewingID, piece.id)
        XCTAssertEqual(model.query, "Bach"); XCTAssertEqual(model.selectedID, "mutopia-61")
        finish?()
        XCTAssertNil(model.previewingID)
        XCTAssertEqual(stops, 0)
        // Reusing the persistent cache must work even when the network cannot.
        let offline = MusicLibraryModel(cache: CatalogCache(directory: directory.appendingPathComponent("preview"), transport: LibraryTransport(data: Data(), failure: true)))
        offline.preview(piece, play: play, stop: { stops += 1 })
        try await waitForDownload(offline)
        XCTAssertEqual(starts, 2)
        offline.preview(piece, play: play, stop: { stops += 1 })
        XCTAssertEqual(starts, 2); XCTAssertEqual(stops, 1); XCTAssertNil(offline.previewingID)
    }

    func testSwitchingPreviewAndOpeningPracticeStopOldAudioAndIgnoreOldCompletion() async throws {
        let (piece, midi, _) = try fixture()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(piece)) as? [String: Any])
        object["id"] = "another-edition"
        let other = try JSONDecoder().decode(CatalogPiece.self, from: JSONSerialization.data(withJSONObject: object))
        let model = MusicLibraryModel(cache: CatalogCache(directory: directory.appendingPathComponent("switch"), transport: LibraryTransport(data: midi)))
        var oldFinish: (() -> Void)?, stops = 0
        model.preview(piece, play: { _, ended in oldFinish = ended; return true }, stop: { stops += 1 })
        try await waitForDownload(model)
        model.preview(other, play: { _, _ in true }, stop: { stops += 1 })
        try await waitForDownload(model)
        XCTAssertEqual(stops, 1)
        oldFinish?()
        XCTAssertEqual(model.previewingID, other.id)
        var opened = false
        model.open(piece) { _ in opened = true; return true }
        try await waitForDownload(model)
        XCTAssertTrue(opened); XCTAssertEqual(stops, 2); XCTAssertNil(model.previewingID)
    }

    func testPreviewCancellationAndErrorsClearPlaybackState() async throws {
        let (piece, midi, _) = try fixture()
        let slow = MusicLibraryModel(cache: CatalogCache(directory: directory.appendingPathComponent("cancelPreview"), transport: LibraryTransport(data: midi, delayed: true)))
        var played = false
        slow.preview(piece, play: { _, _ in played = true; return true }, stop: {})
        try await Task.sleep(nanoseconds: 20_000_000)
        slow.cancel()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(played); XCTAssertNil(slow.previewingID); XCTAssertNil(slow.error)
        let failure = MusicLibraryModel(cache: CatalogCache(directory: directory.appendingPathComponent("failedPreview"), transport: LibraryTransport(data: Data(), failure: true)))
        failure.preview(piece, play: { _, _ in played = true; return true }, stop: {})
        try await waitForDownload(failure)
        XCTAssertFalse(played); XCTAssertNil(failure.previewingID); XCTAssertNotNil(failure.error)
        let noAudio = MusicLibraryModel(cache: CatalogCache(directory: directory.appendingPathComponent("noAudio"), transport: LibraryTransport(data: midi)))
        noAudio.preview(piece, play: { _, _ in false }, stop: {})
        try await waitForDownload(noAudio)
        XCTAssertNil(noAudio.previewingID)
        XCTAssertTrue(noAudio.error?.contains("audio output") == true)
    }

    func testLivePreviewPreservesPracticePieceAndHistoryAndFinishes() async throws {
        let player = try player(), (piece, _, url) = try fixture()
        XCTAssertTrue(player.openCatalogPiece(url, piece: piece, tutored: false))
        let pendingURL = directory.appendingPathComponent("unfinished.mid")
        try MIDIFile.write(notes: [NoteEvent(pitch: 60, onset: 0, offset: 0.5, velocity: 80),
                                   NoteEvent(pitch: 62, onset: 4, offset: 4.5, velocity: 80)]).write(to: pendingURL)
        player.loadReference(pendingURL)
        player.setModeNow(.wait)
        player.mouseDown(on: 60); player.mouseUp()
        XCTAssertEqual(player.phase, .recording)
        player.tab = .musicLibrary
        try await Task.sleep(nanoseconds: 20_000_000)
        let id = player.currentPieceID, score = player.scoreID
        let recent = player.learnerSettings.recentPieces.count
        var finished = false
        let started = player.previewCatalogPiece(url) { finished = true }
        defer { player.preview.stop() }
        try XCTSkipUnless(started, "No audio output is available for native piano preview")
        XCTAssertNotNil(player.preview.playingID)
        XCTAssertEqual(player.tab, .musicLibrary)
        XCTAssertEqual(player.currentPieceID, id); XCTAssertEqual(player.scoreID, score)
        XCTAssertEqual(player.learnerSettings.recentPieces.count, recent)
        for _ in 0..<150 where !finished { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(finished); XCTAssertNil(player.preview.playingID)
        XCTAssertEqual(player.phase, .recording, "Preview must preserve an unfinished practice take")
        XCTAssertEqual(player.currentPieceID, id)
        let learner = try XCTUnwrap(player.learner), pieceID = try XCTUnwrap(id)
        XCTAssertTrue(player.learnerStore.history(for: learner.id).takes(for: pieceID).isEmpty)
    }

    func testCardPreviewInterruptsLibraryAndClearsItsControls() async throws {
        let player = try player(), (piece, midi, url) = try fixture()
        player.tab = .musicLibrary
        try await Task.sleep(nanoseconds: 20_000_000)
        let model = MusicLibraryModel(cache: CatalogCache(directory: directory.appendingPathComponent("sharedPreview"), transport: LibraryTransport(data: midi)))
        var started = false
        model.preview(piece, play: { url, ended in
            started = player.previewCatalogPiece(url, onFinish: ended)
            return started
        }, stop: { player.preview.stop() })
        try await waitForDownload(model)
        defer { player.preview.stop() }
        try XCTSkipUnless(started, "No audio output is available for native piano preview")
        XCTAssertEqual(model.previewingID, piece.id)
        XCTAssertTrue(player.preview.play("lesson-card", url: url))
        XCTAssertNil(model.previewingID)
        XCTAssertEqual(player.preview.playingID, "lesson-card")
        model.cancel()
        XCTAssertEqual(player.preview.playingID, "lesson-card", "A stale library stop must not silence the new card")
        player.tab = .books
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(player.preview.playingID)
    }

    func testLibraryPreviewCanReplaceListenAndListenCanReplacePreview() async throws {
        let player = try player(), (_, _, url) = try fixture()
        player.loadReference(url, remember: false)
        player.tab = .musicLibrary
        try await Task.sleep(nanoseconds: 20_000_000)
        player.startAudition()
        try XCTSkipUnless(player.isAuditioning, "No piano audio output is available")
        defer { player.preview.stop(); player.stopAudition() }
        var ended = false
        XCTAssertTrue(player.previewCatalogPiece(url) { ended = true })
        XCTAssertFalse(player.isAuditioning)
        XCTAssertNotNil(player.preview.playingID)
        // The replaced Listen timer must not stop the newly started preview.
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNotNil(player.preview.playingID)
        player.startAudition()
        XCTAssertTrue(ended)
        XCTAssertNil(player.preview.playingID)
        XCTAssertTrue(player.isAuditioning)
    }

}
#endif
