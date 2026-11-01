import XCTest
@testable import PianoPadState

final class LearnerStoreTests: XCTestCase {
    private var base: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("LearnerStoreTests-\(UUID().uuidString)", isDirectory: true)
        suiteName = "LearnerStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> LearnerStore {
        LearnerStore(baseURL: base, defaults: defaults)
    }

    // MARK: Learners

    func testStartsEmptyWithNoFiles() {
        let store = makeStore()
        XCTAssertTrue(store.learners.isEmpty)
        XCTAssertNil(store.activeLearner)
    }

    func testAddRoundTrips() throws {
        let store = makeStore()
        let sam = try store.add(name: "  Sam ", avatar: "🎹", kind: .adult, level: .basics)
        let kid = try store.add(name: "Kid", kind: .child)
        XCTAssertEqual(sam.name, "Sam")                       // trimmed

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.learners, [sam, kid])         // order kept
        XCTAssertEqual(reloaded.learner(kid.id)?.avatar, Learner.defaultAvatar)
        XCTAssertNil(reloaded.learner(kid.id)?.level)
    }

    func testEmptyNameIsRejected() {
        let store = makeStore()
        XCTAssertThrowsError(try store.add(name: "   ", kind: .adult)) {
            XCTAssertEqual($0 as? LearnerStoreError, .emptyName)
        }
        XCTAssertTrue(store.learners.isEmpty)
    }

    func testRenameSetAvatarAndKind() throws {
        let store = makeStore()
        let a = try store.add(name: "A", kind: .adult)
        try store.rename(a.id, to: "Alice")
        try store.setAvatar(a.id, to: "star")
        try store.setKind(a.id, to: .child)
        XCTAssertThrowsError(try store.rename(a.id, to: ""))

        let reloaded = makeStore().learner(a.id)
        XCTAssertEqual(reloaded?.name, "Alice")
        XCTAssertEqual(reloaded?.avatar, "star")
        XCTAssertEqual(reloaded?.kind, .child)
        XCTAssertEqual(reloaded?.createdAt.timeIntervalSince1970 ?? 0,
                       a.createdAt.timeIntervalSince1970, accuracy: 1)
    }

    func testUnknownLearnerThrows() {
        let store = makeStore()
        let id = UUID()
        XCTAssertThrowsError(try store.rename(id, to: "X")) {
            XCTAssertEqual($0 as? LearnerStoreError, .unknownLearner(id))
        }
        XCTAssertThrowsError(try store.delete(id))
        XCTAssertThrowsError(try store.setActive(id))
        XCTAssertThrowsError(try store.save(LearnerSettings(), for: id))
    }

    // MARK: Active learner

    func testActiveLearnerFallsBackToFirst() throws {
        let store = makeStore()
        let a = try store.add(name: "A", kind: .adult)
        let b = try store.add(name: "B", kind: .child)
        XCTAssertEqual(store.activeLearner, a)               // nothing saved yet

        try store.setActive(b.id)
        XCTAssertEqual(makeStore().activeLearner, b)          // survives a relaunch

        defaults.set(UUID().uuidString, forKey: LearnerStore.activeLearnerKey)
        XCTAssertEqual(store.activeLearner, a)               // stale ID
        defaults.set("not a uuid", forKey: LearnerStore.activeLearnerKey)
        XCTAssertEqual(store.activeLearner, a)
    }

    func testDeletingActiveLearnerSwitchesToFirstRemaining() throws {
        let store = makeStore()
        let a = try store.add(name: "A", kind: .adult)
        let b = try store.add(name: "B", kind: .child)
        try store.setActive(a.id)
        try store.delete(a.id)
        XCTAssertEqual(store.activeLearner, b)
        XCTAssertNil(defaults.string(forKey: LearnerStore.activeLearnerKey))

        try store.delete(b.id)
        XCTAssertNil(store.activeLearner)
        XCTAssertTrue(makeStore().learners.isEmpty)
    }

    func testDeletingAnotherLearnerKeepsActive() throws {
        let store = makeStore()
        let a = try store.add(name: "A", kind: .adult)
        let b = try store.add(name: "B", kind: .child)
        try store.setActive(b.id)
        try store.delete(a.id)
        XCTAssertEqual(store.activeLearner, b)
    }

    // MARK: Folders and settings

    func testDeleteRemovesFolder() throws {
        let store = makeStore()
        let a = try store.add(name: "A", kind: .adult)
        let b = try store.add(name: "B", kind: .adult)
        try store.save(LearnerSettings(strictness: "strict"), for: a.id)
        try store.save(LearnerSettings(strictness: "gentle"), for: b.id)
        let extra = store.folder(for: a.id).appendingPathComponent("takes/x.mid")
        try FileManager.default.createDirectory(at: extra.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: extra)

        try store.delete(a.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(for: a.id).path))
        XCTAssertEqual(store.settings(for: b.id).strictness, "gentle")   // others untouched
    }

    func testSettingsDefaultWhenMissing() throws {
        let store = makeStore()
        let a = try store.add(name: "A", kind: .adult)
        XCTAssertEqual(store.settings(for: a.id), LearnerSettings())
        XCTAssertEqual(store.settings(for: a.id).strictness, "rubric")
        XCTAssertEqual(store.settings(for: a.id).missMode, "replayBar")
    }

    func testSettingsRoundTripPerLearner() throws {
        let store = makeStore()
        let a = try store.add(name: "A", kind: .adult)
        let b = try store.add(name: "B", kind: .child)
        let custom = Data(#"{"earlyMs":100}"#.utf8)
        var settings = LearnerSettings(strictness: "custom", customPlayAlong: custom, missMode: "waitForNote")
        settings.remember(RecentPiece(id: .passage("book.pdf#p29"), title: "Ode to Joy"))
        settings.remember(RecentPiece(id: .file(contents: Data([9])), bookmark: Data([1, 2]),
                                      path: "/tmp/song.mid", title: "Song"))
        try store.save(settings, for: a.id)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.settings(for: a.id), settings)
        XCTAssertEqual(reloaded.settings(for: b.id), LearnerSettings())
    }

    func testCorruptSettingsLoadAsDefaults() throws {
        let store = makeStore()
        let a = try store.add(name: "A", kind: .adult)
        try FileManager.default.createDirectory(at: store.folder(for: a.id), withIntermediateDirectories: true)
        try Data("{nope".utf8).write(to: store.folder(for: a.id).appendingPathComponent("settings.json"))
        XCTAssertEqual(store.settings(for: a.id), LearnerSettings())
    }

    /// Setup answers, including a date: settings are written with ISO-8601 dates, so they
    /// must be read the same way or the whole file falls back to defaults.
    func testSetupFieldsRoundTrip() throws {
        let store = makeStore()
        let a = try store.add(name: "A", kind: .adult)
        let settings = LearnerSettings(persona: "kriti", goalSong: "mary", inputSource: "microphone",
                                       onboardedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(settings, for: a.id)
        let reloaded = makeStore().settings(for: a.id)
        XCTAssertEqual(reloaded, settings)
        XCTAssertEqual(reloaded.persona, "kriti")
        XCTAssertEqual(reloaded.onboardedAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testOlderSettingsWithMissingKeysLoad() throws {
        let store = makeStore()
        let a = try store.add(name: "A", kind: .adult)
        try FileManager.default.createDirectory(at: store.folder(for: a.id), withIntermediateDirectories: true)
        try Data(#"{"strictness":"strict"}"#.utf8)
            .write(to: store.folder(for: a.id).appendingPathComponent("settings.json"))
        let settings = store.settings(for: a.id)
        XCTAssertEqual(settings.strictness, "strict")
        XCTAssertEqual(settings.missMode, LearnerSettings.defaultMissMode)
        XCTAssertTrue(settings.recentPieces.isEmpty)
        XCTAssertNil(settings.persona)
        XCTAssertNil(settings.onboardedAt)
        XCTAssertTrue(settings.showsDancers, "the dancers are on unless a grown-up turns them off")
    }

    func testPracticeModeRoundTrips() throws {
        let store = makeStore()
        let a = try store.add(name: "A", kind: .adult)
        XCTAssertNil(store.settings(for: a.id).practiceMode)
        try store.save(LearnerSettings(practiceMode: "playAlong"), for: a.id)
        XCTAssertEqual(makeStore().settings(for: a.id).practiceMode, "playAlong")
    }

    func testDancersSwitchRoundTrips() throws {
        let store = makeStore()
        let a = try store.add(name: "A", kind: .child)
        try store.save(LearnerSettings(dancers: false), for: a.id)
        let reloaded = makeStore().settings(for: a.id)
        XCTAssertEqual(reloaded.dancers, false)
        XCTAssertFalse(reloaded.showsDancers)
    }

    func testCorruptLearnersFileIsMovedAsideNotOverwritten() throws {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let junk = Data("not json".utf8)
        try junk.write(to: base.appendingPathComponent("learners.json"))

        let store = makeStore()
        XCTAssertTrue(store.learners.isEmpty)
        try store.add(name: "A", kind: .adult)

        let files = try FileManager.default.contentsOfDirectory(atPath: base.path)
        let aside = try XCTUnwrap(files.first { $0.hasPrefix("learners.json.unreadable-") })
        XCTAssertEqual(try Data(contentsOf: base.appendingPathComponent(aside)), junk)
        XCTAssertEqual(makeStore().learners.map(\.name), ["A"])
    }

    func testLearnersFileIsVersioned() throws {
        let store = makeStore()
        try store.add(name: "A", kind: .adult)
        let data = try Data(contentsOf: base.appendingPathComponent("learners.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
    }
}

final class LearnerSettingsTests: XCTestCase {
    func testRememberMovesToFrontAndCaps() {
        var s = LearnerSettings()
        for i in 0..<12 { s.remember(RecentPiece(id: .passage("p\(i)"))) }
        XCTAssertEqual(s.recentPieces.count, LearnerSettings.maxRecentPieces)
        XCTAssertEqual(s.recentPieces.first?.id, .passage("p11"))
        XCTAssertEqual(s.recentPieces.last?.id, .passage("p2"))

        s.remember(RecentPiece(id: .passage("p5"), title: "again"))
        XCTAssertEqual(s.recentPieces.first, RecentPiece(id: .passage("p5"), title: "again"))
        XCTAssertEqual(s.recentPieces.filter { $0.id == .passage("p5") }.count, 1)
    }

    func testForget() {
        var s = LearnerSettings()
        s.remember(RecentPiece(id: .passage("a")))
        s.remember(RecentPiece(id: .passage("b")))
        s.forget(.passage("a"))
        XCTAssertEqual(s.recentPieces.map(\.id), [.passage("b")])
    }
}

final class PieceIDTests: XCTestCase {
    func testPassage() {
        let id = PieceID.passage("book.pdf#p29")
        XCTAssertEqual(id.rawValue, "passage:book.pdf#p29")
        XCTAssertTrue(id.isPassage)
        XCTAssertEqual(id.passageID, "book.pdf#p29")
    }

    func testFileHashIsByContent() throws {
        let a = PieceID.file(contents: Data("MThd one".utf8))
        let b = PieceID.file(contents: Data("MThd one".utf8))
        let c = PieceID.file(contents: Data("MThd two".utf8))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertTrue(a.isFile)
        XCTAssertNil(a.passageID)
        XCTAssertEqual(a.rawValue.count, "file:".count + 16)

        // Renaming a file keeps its ID.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = dir.appendingPathComponent("song.mid")
        let renamed = dir.appendingPathComponent("renamed.mid")
        try Data("MThd one".utf8).write(to: first)
        let before = try PieceID.file(at: first)
        try FileManager.default.moveItem(at: first, to: renamed)
        XCTAssertEqual(try PieceID.file(at: renamed), before)
        XCTAssertEqual(before, a)
    }

    func testKnownFNVValues() {
        XCTAssertEqual(PieceID.fnv1a64Hex(Data()), "cbf29ce484222325")
        XCTAssertEqual(PieceID.fnv1a64Hex(Data("a".utf8)), "af63dc4c8601ec8c")
    }

    func testFolderNameIsOnePathComponent() {
        let name = PieceID.passage("Books/thompson.pdf#p12").folderName
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertEqual(name.removingPercentEncoding, "passage:Books/thompson.pdf#p12")
    }

    func testCodesAsPlainString() throws {
        let data = try JSONEncoder().encode([PieceID.passage("x")])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["passage:x"]"#)
    }
}
