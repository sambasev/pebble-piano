import XCTest
@testable import PianoPadState

final class PracticeSessionsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PracticeSessionsTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }

    func testEmptyWithoutAFile() {
        XCTAssertEqual(LearnerHistory(folder: folder).sessions(), [])
        XCTAssertNil(LearnerHistory(folder: folder).lastTimedBlock())
    }

    func testRecordAndReplace() throws {
        let h = LearnerHistory(folder: folder)
        var s = PracticeSession(started: t0, pages: ["p1"])
        try h.recordSession(s)
        s.ended = t0.addingTimeInterval(720)
        s.completedPages = ["p1"]
        s.notesLearned = ["C"]
        try h.recordSession(s)
        let saved = LearnerHistory(folder: folder).sessions()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].completedPages, ["p1"])
        XCTAssertEqual(saved[0].minutes, 12)
        XCTAssertEqual(saved[0].ended, t0.addingTimeInterval(720))
    }

    func testMinutesAreAtLeastOne() {
        XCTAssertEqual(PracticeSession(started: t0).minutes, 1)
    }

    func testOldestFirstAndCapped() throws {
        let h = LearnerHistory(folder: folder)
        try h.recordSession(PracticeSession(started: t0.addingTimeInterval(100)))
        try h.recordSession(PracticeSession(started: t0))
        XCTAssertEqual(h.sessions().map(\.started), [t0, t0.addingTimeInterval(100)])
    }

    func testLastTimedBlockSearchesBack() throws {
        let h = LearnerHistory(folder: folder)
        let timed = TimedBlockResult(unit: "u1", page: "p4", block: 3, notes: 0.9)
        try h.recordSession(PracticeSession(started: t0, lastTimed: timed))
        try h.recordSession(PracticeSession(started: t0.addingTimeInterval(3600)))
        XCTAssertEqual(h.lastTimedBlock(), timed)
    }

    func testResetRemovesSessions() throws {
        let h = LearnerHistory(folder: folder)
        try h.recordSession(PracticeSession(started: t0))
        try h.reset()
        XCTAssertEqual(h.sessions(), [])
    }

    func testOlderFilesDecode() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"[{"started":"2027-01-15T08:00:00Z"}]"#.utf8).write(to: folder.appendingPathComponent("sessions.json"))
        let s = LearnerHistory(folder: folder).sessions()
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].ended, s[0].started)
        XCTAssertEqual(s[0].pages, [])
    }

    // MARK: Streak

    func testDaysThisWeekCountsDistinctDays() {
        // 2027-01-15 is a Friday.
        let friday = utc.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 9))!
        func at(_ dayOffset: Int, hour: Int = 9) -> PracticeSession {
            PracticeSession(started: utc.date(byAdding: .day, value: dayOffset, to: friday)!.addingTimeInterval(Double(hour - 9) * 3600))
        }
        let sessions = [at(-4), at(-4, hour: 18), at(-2), at(0), at(-7), at(3)]
        // Monday, Wednesday and Friday this week; last Friday and next Monday don't count.
        XCTAssertEqual(WeeklyStreak.daysThisWeek(sessions, now: friday, calendar: utc), 3)
        XCTAssertEqual(WeeklyStreak.daysThisWeek([], now: friday, calendar: utc), 0)
    }

    func testMinutesThisWeek() {
        let friday = utc.date(from: DateComponents(year: 2027, month: 1, day: 15, hour: 9))!
        let thisWeek = PracticeSession(started: friday, ended: friday.addingTimeInterval(12 * 60))
        let earlier = PracticeSession(started: friday.addingTimeInterval(-86_400 * 2), ended: friday.addingTimeInterval(-86_400 * 2 + 5 * 60))
        let lastWeek = PracticeSession(started: friday.addingTimeInterval(-86_400 * 7), ended: friday.addingTimeInterval(-86_400 * 7 + 30 * 60))
        XCTAssertEqual(WeeklyStreak.minutesThisWeek([thisWeek, earlier, lastWeek], now: friday, calendar: utc), 17)
    }

    func testStreakLabel() {
        XCTAssertEqual(WeeklyStreak.label(days: 1), "1 day this week")
        XCTAssertEqual(WeeklyStreak.label(days: 3), "3 days this week")
    }
}
