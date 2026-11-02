#if os(macOS)
import PianoGraderCore
import PianoLessons
import PianoPadState
import XCTest
@testable import PianoPad

final class StudentOverviewTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15, a Friday
    private let lesson = PieceID(rawValue: "lesson:unit1/p1-ex1/0")
    private let song = PieceID.file(contents: Data("song".utf8))

    private func take(daysAgo: Double, _ piece: PieceID, pitch: Int = 0, timing: Int = 0, tempo: Int = 0,
                      score: Double = 0.9, bars: [Int] = []) -> StudentOverview.Take {
        StudentOverview.Take(
            date: now.addingTimeInterval(-daysAgo * 86_400), piece: piece, score: score, passed: score >= 0.95,
            tally: MistakeTally(pitch: pitch, early: timing, tempo: tempo, expected: 20),
            tempoDeviation: tempo > 0 ? 0.2 : 0.02,
            spots: bars.map { .init(category: .pitch, measure: $0) })
    }

    func testRangeBucketsByDayAndSplitsLessonsFromPieces() {
        let o = StudentOverview.build(
            takes: [take(daysAgo: 40, song), take(daysAgo: 2, lesson), take(daysAgo: 2, song), take(daysAgo: 0, lesson)],
            sessions: [PracticeSession(started: now.addingTimeInterval(-2 * 86_400), ended: now.addingTimeInterval(-2 * 86_400 + 600),
                                       completedPages: ["p1"])],
            range: .week, now: now, calendar: calendar)
        XCTAssertEqual(o.takes.count, 3, "the take 40 days ago is outside the week")
        XCTAssertEqual(o.bucketUnit, .day)
        XCTAssertEqual(o.buckets.count, 2)
        XCTAssertEqual(o.buckets[0].lessonTakes, 1)
        XCTAssertEqual(o.buckets[0].otherTakes, 1)
        XCTAssertEqual(o.minutes, 10)
        XCTAssertEqual(o.pagesCompleted, 1)
    }

    func testLongRangesBucketByWeek() {
        let o = StudentOverview.build(takes: [take(daysAgo: 80, song), take(daysAgo: 1, song)], sessions: [],
                                      range: .quarter, now: now, calendar: calendar)
        XCTAssertEqual(o.bucketUnit, .weekOfYear)
    }

    func testRatesArePer100Notes() {
        let o = StudentOverview.build(takes: [take(daysAgo: 0, song, pitch: 2, timing: 1, tempo: 1)], sessions: [],
                                      range: .week, now: now, calendar: calendar)
        XCTAssertEqual(o.buckets[0].rate(.pitch), 10)
        XCTAssertEqual(o.buckets[0].rate(.timing), 5)
        XCTAssertEqual(o.buckets[0].rate(.tempo), 100, "tempo is the share of takes")
    }

    func testTrendsCompareEarlierAndRecentHalves() {
        let takes = [take(daysAgo: 6, song, pitch: 4), take(daysAgo: 5, song, pitch: 4, timing: 2),
                     take(daysAgo: 2, song, timing: 2), take(daysAgo: 1, song, timing: 2)]
        let o = StudentOverview.build(takes: takes, sessions: [], range: .week, now: now, calendar: calendar)
        let pitch = o.trends.first { $0.category == .pitch }!
        XCTAssertEqual(pitch.earlier, 20)
        XCTAssertEqual(pitch.recent, 0)
        XCTAssertEqual(pitch.change, -1)
        XCTAssertEqual(o.focus?.category, .timing, "timing is what's left lately")
        XCTAssertTrue(StudentOverview.build(takes: Array(takes.prefix(3)), sessions: [], range: .week,
                                            now: now, calendar: calendar).trends.isEmpty)
    }

    func testTroubleSpotsNeedTwoTakesAndGroupLessonBlocks() {
        let other = PieceID(rawValue: "lesson:unit1/p1-ex1/1")
        let o = StudentOverview.build(
            takes: [take(daysAgo: 1, lesson, bars: [3, 3, 5]), take(daysAgo: 0, other, bars: [3]), take(daysAgo: 0, song, bars: [7])],
            sessions: [], range: .week, now: now, calendar: calendar)
        XCTAssertEqual(o.troubleSpots.count, 1)
        XCTAssertEqual(o.troubleSpots[0].piece.rawValue, "lesson:unit1/p1-ex1")
        XCTAssertEqual(o.troubleSpots[0].measure, 3)
        XCTAssertEqual(o.troubleSpots[0].count, 2)
        XCTAssertEqual(o.pieces.first?.takes, 2)
    }

    func testTutorTakesAndMinutesAreTheirOwn() {
        var tutored = take(daysAgo: 0, song)
        tutored.tutored = true
        let o = StudentOverview.build(
            takes: [tutored, take(daysAgo: 0, song), take(daysAgo: 0, lesson)],
            sessions: [PracticeSession(started: now.addingTimeInterval(-3600), kind: .tutor, activeSeconds: 600, takes: 1),
                       PracticeSession(started: now.addingTimeInterval(-7200), ended: now.addingTimeInterval(-6900))],
            range: .week, now: now, calendar: calendar)
        XCTAssertEqual(o.buckets[0].tutorTakes, 1)
        XCTAssertEqual(o.buckets[0].lessonTakes, 1)
        XCTAssertEqual(o.buckets[0].otherTakes, 1)
        XCTAssertEqual(o.minutes, 15)
        XCTAssertEqual(o.tutorMinutes, 10)
        XCTAssertEqual(o.pieces.first { $0.piece == song }?.tutored, true)
    }

    func testTutorDrillBarsMapToThePiecesBars() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StudentOverview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = LearnerHistory(folder: folder)
        let report = """
        {"passed":false,"rubricLevel":"beginner","levels":[],"flags":[{"kind":"wrongPitch","position":{"measure":2,"beat":1},"message":""}],
         "results":[],"notes":{"expected":10,"correct":9,"wrongPitch":1,"missed":0,"extra":0,"ignoredLeading":0,"ignoredTrailing":0,
         "accuracy":0.9,"score":0.9}}
        """
        let saved = try history.record(piece: song, midi: Data(), report: Data(report.utf8), score: 0.9, passed: false,
                                       contributesToProgress: false)
        let exercise = PracticeExercise(kind: .slow, measures: 5...6, tempoPercent: 70)
        let context = TutorAttemptContext(exercise: exercise, actualTempoPercent: 70, mode: "wait", printedMeasures: [5, 6])
        try JSONEncoder().encode(context).write(to: saved.reportURL.deletingPathExtension().appendingPathExtension("tutor.json"))
        let takes = history.overviewTakes()
        XCTAssertEqual(takes.count, 1)
        XCTAssertTrue(takes[0].tutored)
        XCTAssertEqual(takes[0].spots, [.init(category: .pitch, measure: 6)])
    }

    func testReadsTakesFromHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StudentOverview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let history = LearnerHistory(folder: folder)
        let report = """
        {"passed":false,"rubricLevel":"beginner","levels":[],"flags":[{"kind":"late","position":{"measure":2,"beat":1},"message":""}],
         "results":[],"notes":{"expected":10,"correct":8,"wrongPitch":1,"missed":1,"extra":0,"ignoredLeading":0,"ignoredTrailing":0,
         "accuracy":0.8,"score":0.8}}
        """
        try history.record(piece: lesson, midi: Data(), report: Data(report.utf8), score: 0.8, passed: false)
        try history.record(piece: song, midi: Data(), report: Data("not json".utf8), score: 0, passed: false)
        let takes = history.overviewTakes()
        XCTAssertEqual(takes.count, 1, "unreadable reports are skipped")
        XCTAssertEqual(takes[0].piece, lesson)
        XCTAssertEqual(takes[0].tally, MistakeTally(pitch: 1, missed: 1, late: 1, expected: 10))
        XCTAssertEqual(takes[0].spots, [.init(category: .timing, measure: 2)])
    }
}
#endif
