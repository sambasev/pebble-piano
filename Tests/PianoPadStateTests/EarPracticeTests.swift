import XCTest
@testable import PianoPadState

final class EarPracticeTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func testOpeningWithoutInteractionDoesNotEarnCredit() {
        var tracker = EarPracticeTracker()
        tracker.tick(at: start)
        tracker.tick(at: start.addingTimeInterval(120))
        XCTAssertNil(tracker.finish(at: start.addingTimeInterval(130)))
    }

    func testPartialPracticeCountsButIdleAndBackgroundDoNot() {
        var tracker = EarPracticeTracker()
        tracker.interact(at: start)
        tracker.tick(at: start.addingTimeInterval(10))
        tracker.setForeground(false, at: start.addingTimeInterval(15))
        tracker.setForeground(true, at: start.addingTimeInterval(300))
        tracker.interact(at: start.addingTimeInterval(310), answered: true)
        tracker.tick(at: start.addingTimeInterval(340))
        let result = tracker.finish(at: start.addingTimeInterval(1000))!
        XCTAssertEqual(result.activeSeconds, 75) // 15 foreground seconds + 60 after the answer.
        XCTAssertEqual(result.earQuestionsAnswered, 1)
        XCTAssertTrue(result.earQuizzes.isEmpty)
        XCTAssertEqual(result.kind, .earTraining)
        XCTAssertNil(tracker.current)
        XCTAssertNil(tracker.finish(at: start.addingTimeInterval(1001)))
    }

    func testCompletedQuizIsRecordedExactlyOnceAndIdleIsTwentyMinutes() {
        var tracker = EarPracticeTracker()
        let quiz = EarQuizSummary(id: "one", level: 2, stage: 3, correct: 8, total: 10)
        tracker.complete(quiz, at: start)
        tracker.complete(quiz, at: start)
        XCTAssertEqual(tracker.current?.earQuizzes, [quiz])
        XCTAssertFalse(tracker.isIdle(at: start.addingTimeInterval(1199)))
        XCTAssertTrue(tracker.isIdle(at: start.addingTimeInterval(1200)))
    }

    func testLegacySessionsRemainLessonsAndNewSessionsRoundTrip() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(PracticeSession.self, from: Data(#"{"started":"2027-01-15T08:00:00Z"}"#.utf8))
        XCTAssertEqual(old.kind, .lesson)
        XCTAssertNil(old.activeSeconds)
        XCTAssertTrue(old.earQuizzes.isEmpty)
        XCTAssertEqual(old.earQuestionsAnswered, 0)
        var tracker = EarPracticeTracker()
        tracker.complete(EarQuizSummary(id: "quiz", level: 8, stage: 3, correct: 9, total: 10), at: start)
        let session = tracker.finish(at: start.addingTimeInterval(12))!
        XCTAssertEqual(try JSONDecoder().decode(PracticeSession.self, from: JSONEncoder().encode(session)), session)
    }

    func testSharedTotalsAndCheckpointReplacementDoNotDoubleCount() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = LearnerHistory(folder: folder)
        let lesson = PracticeSession(started: start, ended: start.addingTimeInterval(600))
        var ear = PracticeSession(started: start, kind: .earTraining, activeSeconds: 120)
        try history.recordSession(lesson)
        try history.recordSession(ear)
        ear.activeSeconds = 180
        try history.recordSession(ear)
        XCTAssertEqual(history.sessions().count, 2)
        let today = PracticeTotals.today(history.sessions() + [ear], now: start)
        XCTAssertEqual(today.count, 2)
        XCTAssertEqual(today.reduce(0) { $0 + $1.minutes }, 13)
        XCTAssertEqual(WeeklyStreak.daysThisWeek(today, now: start), 1)
        XCTAssertEqual(WeeklyStreak.minutesThisWeek(today, now: start), 13)
    }

    func testResetClearsEarProgressAndSessionsButKeepsSettings() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = LearnerHistory(folder: folder)
        try history.saveEarTrainingProgress(Data("progress".utf8))
        try history.recordSession(PracticeSession(started: start, kind: .earTraining))
        let settings = folder.appendingPathComponent("settings.json")
        try Data("settings".utf8).write(to: settings)
        try history.reset()
        XCTAssertNil(history.earTrainingProgress())
        XCTAssertTrue(history.sessions().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: settings.path))
    }
}
