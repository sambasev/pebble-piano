import XCTest
@testable import PianoAI

final class BarMergeAlignmentTests: XCTestCase {
    /// A system with three bars on the page holding 1, 2 and 3 upper-staff notes.
    func system() -> NoteheadGeometry.System {
        let staff = NoteheadGeometry.Staff(lines: [10, 20, 30, 40, 50], spacing: 10)
        let low = NoteheadGeometry.Staff(lines: [110, 120, 130, 140, 150], spacing: 10)
        func head(_ x: Double) -> NoteheadGeometry.Head {
            NoteheadGeometry.Head(x: x, y: 25, position: 5, offset: 0, filled: true, pitch: "C5")
        }
        return NoteheadGeometry.System(upper: staff, lower: low,
                                       upperHeads: [head(50), head(130), head(170), head(220), head(250), head(280)],
                                       lowerHeads: [], barEdges: [0, 100, 200, 300])
    }

    func measure(_ notes: Int) -> SystemReading.Measure {
        SystemReading.Measure(
            upper: .init(clef: .treble, notes: (0..<notes).map { _ in .init(position: 5, duration: .quarter) }),
            lower: .init(clef: .treble, notes: [.init(rest: true, position: 4, duration: .whole)]))
    }

    func testOneToOneWhenCountsAgree() {
        let bars = BarMerge.merge(SystemReading(measureCount: 3, measures: [measure(1), measure(2), measure(3)]), system())
        XCTAssertEqual(bars.map(\.pageBar), [0, 1, 2])
        XCTAssertTrue(bars.allSatisfy(\.isTrusted))
    }

    func testABarTheReadingSkippedIsAddedAndFlagged() {
        let bars = BarMerge.merge(SystemReading(measureCount: 2, measures: [measure(1), measure(3)]), system())
        XCTAssertEqual(bars.count, 3)
        XCTAssertEqual(bars.map(\.pageBar), [0, 1, 2])
        XCTAssertTrue(bars[0].isTrusted)
        XCTAssertEqual(bars[1].upperStatus, .flagged(.skippedByReading))
        XCTAssertTrue(bars[1].upper.isEmpty)
        XCTAssertTrue(bars[2].isTrusted, "the bars after a skipped one are still checked")
    }

    func testABarNotOnThePageIsFlagged() {
        let bars = BarMerge.merge(SystemReading(measureCount: 4, measures: [measure(1), measure(2), measure(5), measure(3)]), system())
        XCTAssertEqual(bars.map(\.pageBar), [0, 1, nil, 2])
        XCTAssertEqual(bars[2].upperStatus, .flagged(.notOnPage))
        XCTAssertTrue(bars[3].isTrusted)
    }

    func testNarrowBarsFromRepeatSignsAreFolded() {
        // A start-repeat bar line just after the clef mustn't make an empty first bar.
        XCTAssertEqual(NoteheadGeometry.foldNarrowBars([100, 115, 300, 500, 512], spacing: 10), [100, 300, 512])
    }

    func testNaturalsArePrintedOnlyToCancel() {
        let n = { (acc: SystemReading.Accidental) in
            BarMerge.Note(note: .init(position: 3, duration: .quarter, accidental: acc), clef: .treble)
        }
        let bar = BarMerge.Bar(upper: [n(.natural), n(.sharp), n(.natural), n(.none)], lower: [],
                               upperStatus: .confirmed, lowerStatus: .confirmed, pageBar: 0)
        let events = ScoreWriter.write([bar], title: "").score.measures[0].events(onStaff: 0)
        XCTAssertEqual(events.map { $0.notes.first?.accidental }, [nil, 1, 0, nil])
    }
}
