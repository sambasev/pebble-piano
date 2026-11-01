import XCTest
@testable import PianoPadState

final class LearnerHistoryTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LearnerHistoryTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private let ode = PieceID.passage("book.pdf#ode")
    private let song = PieceID.file(contents: Data("MThd song".utf8))

    func testDrillSavesTakeWithoutWholePieceProgress() throws {
        let h = LearnerHistory(folder: folder)
        try h.record(piece: ode, midi: Data(), report: Data(), score: 0.4, passed: false)
        let before = h.progress(for: ode)
        try h.record(piece: ode, midi: Data(), report: Data(), score: 1, passed: true, contributesToProgress: false)
        XCTAssertEqual(h.takes(for: ode).count, 2)
        XCTAssertEqual(h.progress(for: ode), before)
        XCTAssertNil(h.progress(for: ode)?.completedAt)
    }

    func testEmptyWithNoFiles() {
        let h = LearnerHistory(folder: folder)
        XCTAssertTrue(h.progress().isEmpty)
        XCTAssertTrue(h.takes(for: ode).isEmpty)
        XCTAssertNoThrow(try h.reset())
    }

    func testRecordSavesTakeAndReport() throws {
        let h = LearnerHistory(folder: folder)
        let date = Date(timeIntervalSince1970: 1_800_000_000.25)
        let take = try h.record(piece: ode, midi: Data([1, 2, 3]), report: Data(#"{"passed":false}"#.utf8),
                                score: 0.6, passed: false, at: date)
        XCTAssertEqual(try Data(contentsOf: take.midiURL), Data([1, 2, 3]))
        XCTAssertEqual(try Data(contentsOf: take.reportURL), Data(#"{"passed":false}"#.utf8))
        XCTAssertEqual(take.midiURL.deletingLastPathComponent().lastPathComponent, ode.folderName)

        let listed = h.takes(for: ode)
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].midiURL.lastPathComponent, take.midiURL.lastPathComponent)
        XCTAssertEqual(listed[0].date.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(h.takes(for: song).isEmpty)
    }

    func testProgressAccumulates() throws {
        let h = LearnerHistory(folder: folder)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        try h.record(piece: ode, midi: Data(), report: Data(), score: 0.5, passed: false, at: t0)
        try h.record(piece: ode, midi: Data(), report: Data(), score: 0.9, passed: true, at: t0 + 60)
        try h.record(piece: ode, midi: Data(), report: Data(), score: 0.7, passed: false, at: t0 + 120)
        try h.record(piece: song, midi: Data(), report: Data(), score: 1.4, passed: false, at: t0 + 180)

        let p = try XCTUnwrap(LearnerHistory(folder: folder).progress(for: ode))   // reloaded
        XCTAssertEqual(p.attempts, 3)
        XCTAssertEqual(p.bestScore, 0.9, accuracy: 1e-9)
        XCTAssertEqual(p.lastScore, 0.7, accuracy: 1e-9)
        XCTAssertEqual(p.lastPlayed.timeIntervalSince1970, (t0 + 120).timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(p.completedAt?.timeIntervalSince1970 ?? 0, (t0 + 60).timeIntervalSince1970, accuracy: 1)  // first pass
        XCTAssertTrue(p.isCompleted)

        let s = try XCTUnwrap(h.progress(for: song))
        XCTAssertEqual(s.bestScore, 1)                          // clamped
        XCTAssertFalse(s.isCompleted)
        XCTAssertEqual(h.takes(for: ode).count, 3)
    }

    func testTakesInTheSameMillisecondDontOverwrite() throws {
        let h = LearnerHistory(folder: folder)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try h.record(piece: ode, midi: Data([1]), report: Data(), score: 0, passed: false, at: date)
        try h.record(piece: ode, midi: Data([2]), report: Data(), score: 0, passed: false, at: date)
        let takes = h.takes(for: ode)
        XCTAssertEqual(takes.count, 2)
        XCTAssertEqual(Set(try takes.map { try Data(contentsOf: $0.midiURL) }), [Data([1]), Data([2])])
    }

    func testResetKeepsSettings() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let suite = "LearnerHistoryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = LearnerStore(baseURL: base, defaults: defaults)
        let a = try store.add(name: "A", kind: .adult)
        try store.save(LearnerSettings(strictness: "strict"), for: a.id)
        let h = store.history(for: a.id)
        try h.record(piece: ode, midi: Data([1]), report: Data(), score: 1, passed: true)

        try h.reset()
        XCTAssertTrue(h.progress().isEmpty)
        XCTAssertTrue(h.takes(for: ode).isEmpty)
        XCTAssertEqual(store.settings(for: a.id).strictness, "strict")
    }

    func testCorruptProgressLoadsEmptyAndIsReplaced() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: folder.appendingPathComponent("progress.json"))
        let h = LearnerHistory(folder: folder)
        XCTAssertTrue(h.progress().isEmpty)
        try h.record(piece: ode, midi: Data(), report: Data(), score: 0.5, passed: false)
        XCTAssertEqual(h.progress(for: ode)?.attempts, 1)
    }

    func testStampRoundTrips() {
        let date = Date(timeIntervalSince1970: 1_800_000_000.123)
        let stem = LearnerHistory.stamp(date)
        XCTAssertEqual(stem.count, 19)
        XCTAssertEqual(LearnerHistory.date(fromStem: stem)?.timeIntervalSince1970 ?? 0, 1_800_000_000.123, accuracy: 0.001)
        XCTAssertEqual(LearnerHistory.date(fromStem: stem + "-2")?.timeIntervalSince1970 ?? 0, 1_800_000_000.123, accuracy: 0.001)
    }
}
