import XCTest
import PianoGraderCore
@testable import PianoLessons

final class StarsTests: XCTestCase {
    private func summary(_ notes: Double, _ timing: Double?, help: Bool = false) -> PerformanceSummary {
        PerformanceSummary(notes: notes, timing: timing, helpUsed: help)
    }

    func testStarBoundaries() {
        XCTAssertEqual(Stars.compute(summary(0.79, 1)), 0)
        XCTAssertEqual(Stars.compute(summary(0.80, 0)), 1, "one star is notes only")
        XCTAssertEqual(Stars.compute(summary(0.90, 0.59)), 1)
        XCTAssertEqual(Stars.compute(summary(0.90, 0.60)), 2)
        XCTAssertEqual(Stars.compute(summary(0.94, 1)), 2)
        XCTAssertEqual(Stars.compute(summary(0.95, 0.79)), 2)
        XCTAssertEqual(Stars.compute(summary(0.95, 0.80)), 3)
        XCTAssertEqual(Stars.compute(summary(1, 1)), 3)
    }

    func testHelpCapsAtTwoStars() {
        XCTAssertEqual(Stars.compute(summary(1, 1, help: true)), 2)
        XCTAssertEqual(Stars.compute(summary(0.85, 1, help: true)), 1)
    }

    func testUnmeasuredTimingCountsAsMet() {
        XCTAssertEqual(Stars.compute(summary(0.96, nil)), 3)
        XCTAssertEqual(Stars.compute(summary(0.91, nil)), 2)
    }

    func testTimingScoreAgainstTheBeginnerRubric() {
        let r = Rubric.beginner   // max_mean_ioi_error 0.25
        XCTAssertEqual(Stars.timingScore(meanIOIError: 0, rubric: r), 1, accuracy: 1e-9)
        XCTAssertEqual(Stars.timingScore(meanIOIError: 0.10, rubric: r), 0.8, accuracy: 1e-9)
        XCTAssertEqual(Stars.timingScore(meanIOIError: 0.20, rubric: r), 0.6, accuracy: 1e-9)
        XCTAssertEqual(Stars.timingScore(meanIOIError: 0.25, rubric: r), 0.5, accuracy: 1e-9, "the pass limit")
        XCTAssertEqual(Stars.timingScore(meanIOIError: 0.80, rubric: r), 0, accuracy: 1e-9)
    }

    func testTimingScoreWithAZeroLimit() {
        var r = Rubric.beginner
        r.rhythm.maxMeanIOIError = 0
        XCTAssertEqual(Stars.timingScore(meanIOIError: 0, rubric: r), 1)
        XCTAssertEqual(Stars.timingScore(meanIOIError: 0.01, rubric: r), 0)
    }

    func testFromAGradeReport() throws {
        let json = """
        {
          "passed": true, "rubricLevel": "beginner", "levels": [], "flags": [], "results": [],
          "notes": { "expected": 14, "correct": 13, "wrongPitch": 1, "missed": 0, "extra": 0,
                     "ignoredLeading": 0, "ignoredTrailing": 0, "accuracy": 0.9286, "score": 0.9286 },
          "timing": { "anchors": 12, "fittedBPM": 88, "targetBPM": 92, "tempoDeviation": -0.04,
                      "meanIOIError": 0.15, "maxIOIError": 0.3, "steadinessCV": 0.1 }
        }
        """
        let report = try JSONDecoder().decode(GradeReport.self, from: Data(json.utf8))
        let s = Stars.summary(report: report, rubric: .beginner, helpUsed: false)
        XCTAssertEqual(s.notes, 0.9286, accuracy: 1e-9)
        XCTAssertEqual(s.timing ?? -1, 0.7, accuracy: 1e-9)
        XCTAssertEqual(Stars.compute(report: report, rubric: .beginner, helpUsed: false), 2)
    }
}
