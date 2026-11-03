import XCTest
import PianoGraderCore
@testable import PianoLessons

final class MistakeTrendsTests: XCTestCase {
    /// A report with `errors` as (measure, kind, expected, played); every other measure 1–4 correct.
    private func report(score: Double, passed: Bool = false, bpm: Double? = nil,
                        errors: [(Int, String, Int?, Int?)] = [], measures: ClosedRange<Int> = 1...4) throws -> GradeReport {
        var results: [[String: Any]] = measures.map { ["kind": "correct", "expectedPitch": 60, "playedPitch": 60,
                                                       "position": ["measure": $0, "beat": 1.0]] }
        for (m, kind, e, p) in errors {
            var r: [String: Any] = ["kind": kind, "position": ["measure": m, "beat": 2.0]]
            if let e { r["expectedPitch"] = e }
            if let p { r["playedPitch"] = p }
            results.append(r)
        }
        var json: [String: Any] = [
            "passed": passed, "rubricLevel": "beginner", "levels": [], "flags": [], "results": results,
            "notes": ["expected": 8, "correct": 6, "wrongPitch": 1, "missed": 1, "extra": 0,
                      "ignoredLeading": 0, "ignoredTrailing": 0, "accuracy": score, "score": score],
        ]
        if let bpm {
            json["timing"] = ["anchors": 8, "fittedBPM": bpm, "targetBPM": 100.0, "tempoDeviation": 0.1,
                              "meanIOIError": 0.05, "maxIOIError": 0.1, "steadinessCV": 0.1]
        }
        return try JSONDecoder().decode(GradeReport.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: 1_793_000_000 + Double(n) * 86_400) }

    func testRecurringBarsUseTheSlipThatKeepsHappening() throws {
        let takes = try [
            TrendTake(date: day(0), report: report(score: 0.5, errors: [(3, "wrongPitch", 64, 62), (2, "missed", 67, nil)])),
            TrendTake(date: day(1), report: report(score: 0.6, errors: [(3, "wrongPitch", 64, 62)])),
            TrendTake(date: day(2), report: report(score: 0.7, errors: [(3, "missed", 65, nil), (3, "wrongPitch", 64, 62)])),
        ]
        let trends = MistakeTrends(takes)
        XCTAssertEqual(trends.troubleBars, [.init(bar: 3, takesWithErrors: 3, takesCovering: 3, usualSlip: "E4 played as D4")])
        XCTAssertEqual(trends.firstScore, 0.5)
        XCTAssertEqual(trends.latestScore, 0.7)
        XCTAssertNil(trends.recentChange)
        XCTAssertTrue(trends.summary(title: "Ode").contains("bar 3, 3 of 3 takes, usually E4 played as D4"))
    }

    func testDrillTakesAreMappedToPrintedBars() throws {
        // A drill of printed bars 9–10: its local bar 2 is printed bar 10.
        let drill = try report(score: 0.8, errors: [(2, "wrongPitch", 64, 65)], measures: 1...2)
        let takes = [TrendTake(date: day(0), report: drill, printedMeasures: [9, 10], tempoPercent: 60, noteByNote: true),
                     TrendTake(date: day(1), report: drill, printedMeasures: [9, 10], tempoPercent: 70)]
        let trends = MistakeTrends(takes)
        XCTAssertEqual(trends.troubleBars.map(\.bar), [10])
        XCTAssertEqual(trends.fullSpeedTakes, 0)
        XCTAssertTrue(trends.summary(title: "Ode").contains("not evidence the piece is ready"))
    }

    func testTrendAndFullSpeedEvidence() throws {
        var takes: [TrendTake] = []
        for (i, score) in [0.5, 0.5, 0.6, 0.8, 0.85, 0.9].enumerated() {
            takes.append(TrendTake(date: day(i), report: try report(score: score, passed: i == 5, bpm: 90 + Double(i)),
                                   tempoPercent: i >= 4 ? 100 : 70))
        }
        let trends = MistakeTrends(takes)
        let recent: Double = (0.8 + 0.85 + 0.9) / 3, before: Double = (0.5 + 0.5 + 0.6) / 3
        XCTAssertEqual(trends.recentChange ?? 0, recent - before, accuracy: 1e-9)
        XCTAssertEqual(trends.fullSpeedTakes, 2)
        XCTAssertEqual(trends.bestFullSpeedScore, 0.9)
        XCTAssertEqual(trends.latestFullSpeedPassed, true)
        XCTAssertEqual(trends.latestFittedBPM, 95)
        let summary = trends.summary(title: "Ode")
        XCTAssertTrue(summary.contains("improving"))
        XCTAssertTrue(summary.contains("95 BPM against a target of 100"))
        XCTAssertTrue(summary.contains("No bar went wrong in more than one take."))
    }

    func testOnlyTheLatestTakesCountAndNoTakesSaysSo() throws {
        let takes = try (0..<20).map { TrendTake(date: day($0), report: try report(score: Double($0) / 20)) }
        XCTAssertEqual(MistakeTrends(takes.shuffled()).takes, MistakeTrends.takeLimit)
        XCTAssertEqual(MistakeTrends(takes).firstScore, 8.0 / 20)
        XCTAssertEqual(MistakeTrends([]).summary(title: "Ode"), "No saved takes of Ode yet.")
    }
}
