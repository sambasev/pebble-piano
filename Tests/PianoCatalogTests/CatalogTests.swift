import XCTest
import PianoGraderCore
@testable import PianoCatalog

final class CatalogTests: XCTestCase {
    func testBundledCatalogHasThirtyCreditedUniqueEditions() throws {
        let catalog = try MusicCatalog.bundled()
        XCTAssertEqual(catalog.pieces.count, 30)
        XCTAssertEqual(Set(catalog.pieces.map(\.id)).count, 30)
        XCTAssertEqual(Set(catalog.pieces.map(\.sha256)).count, 30)
        XCTAssertEqual(catalog.sourceRevision.count, 40)
        XCTAssertTrue(catalog.pieces.allSatisfy { $0.attribution.contains("Mutopia") && !$0.review.isEmpty })
        XCTAssertTrue(catalog.pieces.contains { $0.license == "CC BY 2.5" })
    }

    func testKeySignaturesAndLegacyUnknownMetadata() throws {
        let catalog = try MusicCatalog.bundled()
        XCTAssertEqual(catalog.pieces.filter { $0.keySignature != nil }.count, 29)
        XCTAssertEqual(catalog.pieces.first { $0.id == "mutopia-228" }?.keySignatureDescription, "2 flats")
        XCTAssertEqual(catalog.pieces.first { $0.id == "mutopia-865" }?.keySignatureDescription, "3 sharps")
        XCTAssertEqual(catalog.pieces.first { $0.id == "mutopia-203" }?.keySignatureDescription, "No sharps or flats")
        XCTAssertNil(catalog.pieces.first { $0.id == "mutopia-59" }?.keySignatureDescription)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(catalog.pieces[0])) as? [String: Any])
        object.removeValue(forKey: "keySignature")
        let legacy = try JSONDecoder().decode(CatalogPiece.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.keySignature)
    }

    func testSearchAndCombinedFilters() throws {
        let pieces = try MusicCatalog.bundled().pieces
        let arabesque = try XCTUnwrap(pieces.first { $0.title.contains("Arabesque") })
        XCTAssertTrue(arabesque.matches(query: "ARABESQUE burgmuller"))
        XCTAssertTrue(arabesque.matches(query: "  ", composer: arabesque.composer, difficulty: arabesque.difficulty))
        XCTAssertFalse(arabesque.matches(query: "Arabesque", composer: "Bach"))
        XCTAssertFalse(arabesque.matches(query: "", difficulty: .advanced))
        XCTAssertFalse(arabesque.matches(query: "not a title"))
    }

    func testRejectsDuplicateIDsMissingAttributionAndBadHash() throws {
        let original = try MusicCatalog.bundled()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        let pieces = try XCTUnwrap(object["pieces"] as? [[String: Any]])
        for field in ["attribution", "sha256"] {
            var changed = pieces
            changed[0][field] = ""
            object["pieces"] = changed
            XCTAssertThrowsError(try MusicCatalog.decode(JSONSerialization.data(withJSONObject: object)))
        }
        object["pieces"] = [pieces[0], pieces[0]]
        XCTAssertThrowsError(try MusicCatalog.decode(JSONSerialization.data(withJSONObject: object)))
    }
}

actor StubTransport: CatalogTransport {
    let data: Data
    let fails: Bool
    let delayed: Bool
    private(set) var calls = 0
    init(data: Data, fails: Bool = false, delayed: Bool = false) {
        self.data = data; self.fails = fails; self.delayed = delayed
    }
    func download(_ url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> Data {
        calls += 1
        progress(0.5)
        if delayed { try await Task.sleep(nanoseconds: 5_000_000_000) }
        if fails { throw URLError(.notConnectedToInternet) }
        return data
    }
}

final class CatalogCacheTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    func midi() -> Data {
        MIDIFile.write(notes: [NoteEvent(pitch: 60, onset: 0, offset: 0.5, velocity: 80)])
    }
    func piece(for data: Data) throws -> CatalogPiece {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(MusicCatalog.bundled().pieces[0])) as? [String: Any])
        object["sha256"] = CatalogCache.digest(data)
        return try JSONDecoder().decode(CatalogPiece.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testDownloadThenReopenOfflineWithIdenticalBytes() async throws {
        let data = midi(), piece = try piece(for: data)
        let transport = StubTransport(data: data)
        let cache = CatalogCache(directory: directory, transport: transport)
        let first = try await cache.prepare(piece)
        XCTAssertEqual(try Data(contentsOf: first), data)
        let again = try await cache.prepare(piece)
        XCTAssertEqual(again, first)
        let calls = await transport.calls
        XCTAssertEqual(calls, 1)
        let offline = CatalogCache(directory: directory, transport: StubTransport(data: Data(), fails: true))
        let offlineURL = try await offline.prepare(piece)
        XCTAssertEqual(offlineURL, first)
        let downloaded = await offline.downloadedIDs(in: [piece])
        XCTAssertEqual(downloaded, [piece.id])
    }

    func testCorruptCacheIsNotDownloadedAndIsReplaced() async throws {
        let data = midi(), piece = try piece(for: data)
        let transport = StubTransport(data: data)
        let cache = CatalogCache(directory: directory, transport: transport)
        let url = try await cache.prepare(piece)
        try Data("corrupt".utf8).write(to: url)
        let downloaded = await cache.downloadedIDs(in: [piece])
        XCTAssertTrue(downloaded.isEmpty)
        _ = try await cache.prepare(piece)
        XCTAssertEqual(try Data(contentsOf: url), data)
        let calls = await transport.calls
        XCTAssertEqual(calls, 2)
    }

    func testChecksumAndMalformedAndEmptyMIDIAreRejectedWithoutCacheFiles() async throws {
        for data in [Data("not MIDI".utf8), MIDIFile.write(notes: [])] {
            let piece = try piece(for: data)
            let cache = CatalogCache(directory: directory, transport: StubTransport(data: data))
            do { _ = try await cache.prepare(piece); XCTFail("Expected invalid MIDI") }
            catch CatalogError.invalidMIDI {} catch { XCTFail("Unexpected error: \(error)") }
        }
        let cache = CatalogCache(directory: directory, transport: StubTransport(data: Data("unexpected edition".utf8)))
        do { _ = try await cache.prepare(piece(for: midi())); XCTFail("Expected checksum failure") }
        catch CatalogError.checksum {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testOfflineFailureDoesNotCreateCache() async throws {
        let cache = CatalogCache(directory: directory, transport: StubTransport(data: Data(), fails: true))
        do { _ = try await cache.prepare(piece(for: midi())); XCTFail("Expected network error") }
        catch let error as URLError { XCTAssertEqual(error.code, .notConnectedToInternet) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testCancellationNeverInstallsFile() async throws {
        let piece = try piece(for: midi())
        let transport = StubTransport(data: midi(), delayed: true)
        let cache = CatalogCache(directory: directory, transport: transport)
        let download = Task { try await cache.prepare(piece) }
        for _ in 0..<100 {
            if await transport.calls > 0 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        download.cancel()
        do { _ = try await download.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        let downloaded = await cache.downloadedIDs(in: [piece])
        XCTAssertTrue(downloaded.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}

private final class StubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = request.url!.path.contains("missing") ? 404 : 200
        let headers = request.url!.path.contains("oversize") ? ["Content-Length": "99999999"] : [:]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("response".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CatalogTransportTests: XCTestCase {
    func testHTTPFailureAndOversizedResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = MutopiaTransport(session: session)
        do { _ = try await transport.download(URL(string: "https://example.test/missing")!) { _ in }; XCTFail("Expected HTTP error") }
        catch CatalogError.http(let status) { XCTAssertEqual(status, 404) }
        do { _ = try await transport.download(URL(string: "https://example.test/oversize")!) { _ in }; XCTFail("Expected size error") }
        catch CatalogError.tooLarge {}
        let success = try await transport.download(URL(string: "https://example.test/ok")!) { _ in }
        XCTAssertEqual(success, Data("response".utf8))
    }
}

final class CatalogCorpusTests: XCTestCase {
    func testAllReviewedMIDIsWithActualReaderAndEngraver() throws {
        guard let path = ProcessInfo.processInfo.environment["MUTOPIA_REVIEW_DIR"] else {
            throw XCTSkip("Set MUTOPIA_REVIEW_DIR to opt into downloaded corpus validation")
        }
        for piece in try MusicCatalog.bundled().pieces {
            let url = URL(fileURLWithPath: path).appendingPathComponent(piece.id + ".mid")
            let data = try Data(contentsOf: url)
            try CatalogCache.validate(data, for: piece)
            let sequence = try MIDIFile.parse(data)
            XCTAssertEqual(piece.keySignature, sequence.keySignature, "Opening signature: \(piece.id)")
            let score = Transcriber().transcribe(sequence, title: piece.title)
            XCTAssertFalse(score.measures.isEmpty, piece.id)
            XCTAssertTrue(sequence.notes.allSatisfy { note in
                let on = note.onsetBeats * 4, off = (note.offsetBeats ?? -1) * 4
                return abs(on - on.rounded()) < 0.015 && abs(off - off.rounded()) < 0.015
            }, piece.id)
            // The renderer must retain every expected pitch at its original onset.
            for note in sequence.notes {
                let onset = Int((note.onsetBeats * 4).rounded())
                XCTAssertTrue(score.measures.contains { measure in
                    measure.events.contains { event in
                        measure.startSixteenth + event.start == onset && event.notes.contains { $0.midi == note.pitch }
                    }
                }, "\(piece.id): lost pitch \(note.pitch) at \(onset)")
            }
        }
    }
}
