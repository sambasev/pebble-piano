import XCTest
@testable import PianoPadState

final class LessonProgressTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LessonProgressTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testPieceIDs() {
        XCTAssertEqual(PieceID.lessonPage(unit: "u1", page: "p2").rawValue, "lesson:u1/p2")
        XCTAssertEqual(PieceID.lesson(unit: "u1", page: "p2", block: 4).rawValue, "lesson:u1/p2/4")
        XCTAssertTrue(PieceID.lesson(unit: "u1", page: "p2", block: 4).isLesson)
        XCTAssertFalse(PieceID.passage("x").isLesson)
        XCTAssertFalse(PieceID.lesson(unit: "u1", page: "p2", block: 4).folderName.contains("/"),
                       "block takes get a single folder")
    }

    func testEmptyWithoutAFile() {
        let h = LearnerHistory(folder: folder)
        XCTAssertTrue(h.lessonProgress().isEmpty)
        XCTAssertNil(h.lessonProgress(unit: "u1", page: "p1"))
        XCTAssertTrue(h.completedPages(unit: "u1").isEmpty)
    }

    func testSavesTheResumePoint() throws {
        let h = LearnerHistory(folder: folder)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try h.saveLessonPosition(unit: "u1", page: "p1", block: 3, at: date)
        let p = try XCTUnwrap(h.lessonProgress(unit: "u1", page: "p1"))
        XCTAssertEqual(p.currentBlock, 3)
        XCTAssertFalse(p.isCompleted)
        XCTAssertEqual(p.lastPlayed, date)
        XCTAssertEqual(LearnerHistory(folder: folder).lessonProgress(unit: "u1", page: "p1"), p, "reloads from disk")
    }

    func testRecordsCompletionsAndBestStars() throws {
        let h = LearnerHistory(folder: folder)
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let second = first.addingTimeInterval(3600)
        try h.saveLessonPosition(unit: "u1", page: "p1", block: 4, at: first)
        try h.recordPageComplete(unit: "u1", page: "p1", stars: 2, flaggedBlocks: [2], at: first)
        try h.recordPageComplete(unit: "u1", page: "p1", stars: 1, flaggedBlocks: [], at: second)

        let p = try XCTUnwrap(h.lessonProgress(unit: "u1", page: "p1"))
        XCTAssertEqual(p.currentBlock, 0, "a finished page starts from the top next time")
        XCTAssertEqual(p.completions, 2)
        XCTAssertEqual(p.bestStars, 2)
        XCTAssertEqual(p.lastStars, 1)
        XCTAssertEqual(p.completedAt, first, "first completion is kept")
        XCTAssertEqual(p.lastPlayed, second)
        XCTAssertEqual(p.flaggedBlocks, [])
    }

    func testCompletedPagesPerUnit() throws {
        let h = LearnerHistory(folder: folder)
        try h.recordPageComplete(unit: "u1", page: "p1", stars: 3, flaggedBlocks: [])
        try h.recordPageComplete(unit: "u1", page: "p3", stars: nil, flaggedBlocks: [])
        try h.saveLessonPosition(unit: "u1", page: "p2", block: 1)
        try h.recordPageComplete(unit: "u10", page: "p9", stars: 1, flaggedBlocks: [])
        XCTAssertEqual(h.completedPages(unit: "u1"), ["p1", "p3"])
        XCTAssertEqual(h.completedPages(unit: "u10"), ["p9"])
    }

    func testOlderOrPartialEntriesDecode() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"lesson:u1/p1":{"bestStars":1}}"#.utf8).write(to: folder.appendingPathComponent("lessons.json"))
        let p = try XCTUnwrap(LearnerHistory(folder: folder).lessonProgress(unit: "u1", page: "p1"))
        XCTAssertEqual(p.bestStars, 1)
        XCTAssertEqual(p.currentBlock, 0)
        XCTAssertEqual(p.completions, 0)
    }

    func testCorruptFileReadsAsEmpty() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: folder.appendingPathComponent("lessons.json"))
        XCTAssertTrue(LearnerHistory(folder: folder).lessonProgress().isEmpty)
    }

    func testResetClearsLessons() throws {
        let h = LearnerHistory(folder: folder)
        try h.recordPageComplete(unit: "u1", page: "p1", stars: 3, flaggedBlocks: [])
        try h.reset()
        XCTAssertTrue(h.lessonProgress().isEmpty)
    }
}
