import XCTest
@testable import PianoGraderCore

final class BookAnnotationsTests: XCTestCase {
    /// Two printed 4/4 measures, played twice (a repeat sign).
    private func passage() -> PassageAnnotation {
        PassageAnnotation(
            id: "test", title: "test", page: 1, reference: "test.mid",
            box: PageRect(x: 0, y: 0, width: 400, height: 100),
            measures: [
                MeasureAnnotation(number: 1, quarters: 4, box: PageRect(x: 0, y: 0, width: 200, height: 100), beatX: [20, 220]),
                MeasureAnnotation(number: 2, quarters: 4, box: PageRect(x: 200, y: 0, width: 200, height: 100), beatX: [220, 420]),
            ],
            playOrder: [1, 2, 1, 2]
        )
    }

    func testLocationWalksThePlayOrder() throws {
        let p = passage()
        let start = try XCTUnwrap(p.location(atQuarter: 0))
        XCTAssertEqual(start.measure.number, 1)
        XCTAssertEqual(start.x, 20, accuracy: 1e-9)

        let beat3 = try XCTUnwrap(p.location(atQuarter: 2))
        XCTAssertEqual(beat3.measure.number, 1)
        XCTAssertEqual(beat3.x, 120, accuracy: 1e-9)

        XCTAssertEqual(p.location(atQuarter: 5)?.measure.number, 2)
        // Quarter 9 is in the repeat: printed measure 1 again.
        let repeatStart = try XCTUnwrap(p.location(atQuarter: 9))
        XCTAssertEqual(repeatStart.measure.number, 1)
        XCTAssertEqual(repeatStart.fraction, 0.25, accuracy: 1e-9)
    }

    func testLapCountsRepeats() {
        let p = passage() // measures 1, 2, then 1, 2 again
        XCTAssertEqual(p.lap(atQuarter: 0), 0)
        XCTAssertEqual(p.lap(atQuarter: 7.9), 0)
        XCTAssertEqual(p.lap(atQuarter: 8), 1)
        XCTAssertEqual(p.lap(atQuarter: 15.9), 1)
        XCTAssertNil(p.lap(atQuarter: 16))
        XCTAssertNil(p.lap(atQuarter: -1))
    }

    func testLocationIsNilOutsideThePassage() {
        let p = passage()
        XCTAssertNil(p.location(atQuarter: -0.1))
        XCTAssertNil(p.location(atQuarter: 16))
    }

    func testPlayheadStaysInsideTheMeasureBox() {
        // beatX of measure 2 runs past its box (420 > 400); x is clamped.
        let m = passage().measures[1]
        XCTAssertEqual(m.x(atFraction: 1), 400, accuracy: 1e-9)
        XCTAssertEqual(m.x(atFraction: -1), 220, accuracy: 1e-9)
    }

    func testPlayedMeasuresMapToPrintedMeasures() {
        let p = passage()
        XCTAssertEqual(p.printedMeasure(forPlayed: 1), 1)
        XCTAssertEqual(p.printedMeasure(forPlayed: 3), 1)
        XCTAssertEqual(p.printedMeasure(forPlayed: 4), 2)
        XCTAssertNil(p.printedMeasure(forPlayed: 5))
        XCTAssertNil(p.printedMeasure(forPlayed: 0))
    }

    func testMistakesInTheRepeatHighlightTheirPrintedMeasure() {
        // Reference: C D E F | G A B C, played twice; the take gets measure 4's first note wrong.
        let bar = [60, 62, 64, 65, 67, 69, 71, 72]
        func seq(_ pitches: [Int]) -> MIDISequence {
            MIDISequence(notes: pitches.enumerated().map { i, p in
                NoteEvent(pitch: p, onset: Double(i) * 0.5, offset: Double(i) * 0.5 + 0.4, onsetBeats: Double(i))
            }, initialTempoBPM: 120)
        }
        var take = bar + bar
        take[12] = 66 // measure 4 (the repeat of printed measure 2), beat 1
        let report = Grader().grade(reference: seq(bar + bar), take: seq(take))
        XCTAssertEqual(passage().measuresWithMistakes(in: report), [2])
    }
}
