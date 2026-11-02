import XCTest
@testable import PianoGraderCore

final class MistakeTallyTests: XCTestCase {
    private func report(wrong: Int = 0, missed: Int = 0, extra: Int = 0, flags: [GradeFlag.Kind] = [],
                        tempoDeviation: Double? = nil, steadiness: Double = 0) -> GradeReport {
        let notes = NoteSummary(expected: 20, correct: 20 - wrong - missed, wrongPitch: wrong, missed: missed, extra: extra,
                                ignoredLeading: 0, ignoredTrailing: 0, accuracy: 0.8, score: 0.8)
        let timing = tempoDeviation.map {
            TimingSummary(anchors: 10, fittedBPM: 100 * (1 + $0), targetBPM: 100, tempoDeviation: $0,
                          meanIOIError: 0.1, maxIOIError: 0.2, steadinessCV: steadiness)
        }
        let pos = ScorePosition(measure: 2, beat: 1)
        return GradeReport(passed: false, rubricLevel: "beginner", levels: [], notes: notes, timing: timing,
                           flags: flags.map { GradeFlag(kind: $0, position: pos, message: "") }, results: [])
    }

    func testSortsNoteMistakesByKind() {
        let t = MistakeTally(report(wrong: 2, missed: 1, extra: 3, flags: [.wrongPitch, .early, .late, .late]))
        XCTAssertEqual(t.pitch, 2)
        XCTAssertEqual(t.missed, 1)
        XCTAssertEqual(t.extra, 3)
        XCTAssertEqual(t.early, 1)
        XCTAssertEqual(t.late, 2)
        XCTAssertEqual(t.timing, 3)
        XCTAssertEqual(t.expected, 20)
        XCTAssertEqual(t.noteMistakes, 9)
        XCTAssertEqual(t.tempo, 0)
    }

    func testTempoCountsRushingDraggingAndWandering() {
        XCTAssertEqual(MistakeTally(report(tempoDeviation: 0.05)).tempo, 0)
        XCTAssertEqual(MistakeTally(report(tempoDeviation: 0.2)).tempo, 1)
        XCTAssertEqual(MistakeTally(report(tempoDeviation: -0.2)).tempo, 1)
        XCTAssertEqual(MistakeTally(report(tempoDeviation: 0, steadiness: 0.3)).tempo, 1)
        XCTAssertEqual(MistakeTally(report()).tempo, 0, "no tempo fitted, no tempo mistake")
    }

    func testAdds() {
        let a = MistakeTally(pitch: 1, early: 1, expected: 10)
        let b = MistakeTally(missed: 2, late: 1, tempo: 1, expected: 5)
        let sum = a + b
        XCTAssertEqual(sum, MistakeTally(pitch: 1, missed: 2, early: 1, late: 1, tempo: 1, expected: 15))
        XCTAssertEqual(sum[.timing], 2)
    }
}
