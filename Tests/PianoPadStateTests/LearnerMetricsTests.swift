import XCTest
@testable import PianoPadState

final class LearnerMetricsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LearnerMetricsTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testEmptyWithoutAFile() {
        let m = LearnerHistory(folder: folder).metrics()
        XCTAssertEqual(m, LearnerMetrics())
        XCTAssertNil(m.secondsFromSetupToFirstNote)
        XCTAssertNil(m.secondsFromLaunchToFirstNote)
    }

    func testSetupThenFirstNote() throws {
        let h = LearnerHistory(folder: folder)
        try h.recordSetup(started: t0, finished: t0.addingTimeInterval(70))
        XCTAssertTrue(try h.recordFirstLessonNote(at: t0.addingTimeInterval(130), appLaunched: t0.addingTimeInterval(-20)))
        let m = LearnerHistory(folder: folder).metrics()
        XCTAssertEqual(m.setupStarted, t0)
        XCTAssertEqual(m.setupFinished, t0.addingTimeInterval(70))
        XCTAssertEqual(m.secondsFromSetupToFirstNote ?? -1, 130, accuracy: 0.001)
        XCTAssertEqual(m.secondsFromLaunchToFirstNote ?? -1, 150, accuracy: 0.001)
    }

    func testEachMomentIsWrittenOnce() throws {
        let h = LearnerHistory(folder: folder)
        try h.recordSetup(started: t0, finished: t0.addingTimeInterval(60))
        try h.recordSetup(started: t0.addingTimeInterval(999), finished: t0.addingTimeInterval(9999))
        XCTAssertTrue(try h.recordFirstLessonNote(at: t0.addingTimeInterval(100), appLaunched: t0))
        XCTAssertFalse(try h.recordFirstLessonNote(at: t0.addingTimeInterval(500), appLaunched: t0))
        let m = h.metrics()
        XCTAssertEqual(m.setupFinished, t0.addingTimeInterval(60))
        XCTAssertEqual(m.firstLessonNote, t0.addingTimeInterval(100))
    }

    func testFirstNoteWithoutSetup() throws {
        // A learner added before setup existed: only the launch measure.
        let h = LearnerHistory(folder: folder)
        try h.recordFirstLessonNote(at: t0.addingTimeInterval(45), appLaunched: t0)
        XCTAssertNil(h.metrics().secondsFromSetupToFirstNote)
        XCTAssertEqual(h.metrics().secondsFromLaunchToFirstNote ?? -1, 45, accuracy: 0.001)
    }

    func testResetKeepsMetrics() throws {
        let h = LearnerHistory(folder: folder)
        try h.recordSetup(started: t0, finished: t0.addingTimeInterval(60))
        try h.reset()
        XCTAssertEqual(h.metrics().setupFinished, t0.addingTimeInterval(60))
    }
}
