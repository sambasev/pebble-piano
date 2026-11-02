import XCTest
@testable import PianoAI

final class BarEditsTests: XCTestCase {
    /// Treble: position 1 is F4, 4 is B4.
    func n(_ position: Int, _ duration: SystemReading.Duration = .quarter, rest: Bool = false) -> BarMerge.Note {
        BarMerge.Note(note: .init(rest: rest, position: position, duration: duration), clef: .treble,
                      head: .init(x: 0, y: 0, position: position, offset: 0, filled: true, pitch: ""))
    }

    func bar(_ upper: [BarMerge.Note], lower: [BarMerge.Note] = []) -> BarMerge.Bar {
        BarMerge.Bar(upper: upper, lower: lower, upperStatus: .confirmed, lowerStatus: .confirmed, pageBar: 0)
    }

    func testMoveKeepsTheLengthAndLeavesRestsAlone() {
        var b = bar([n(1, .half), n(4, rest: true)])
        b.move(.upper, 0, by: 2)
        b.move(.upper, 1, by: 2)
        XCTAssertEqual(b.upper.map(\.note.position), [3, 4])
        XCTAssertEqual(b.upper[0].note.duration, .half)
        XCTAssertNil(b.upper[0].head, "a moved note is no longer the one measured")
    }

    func testAccidentalsCycle() {
        var b = bar([n(1)])
        var seen: [SystemReading.Accidental] = []
        for _ in 0..<4 {
            b.cycleAccidental(.upper, 0)
            seen.append(b.upper[0].note.accidental)
        }
        XCTAssertEqual(seen, [.sharp, .flat, .none, .sharp], "no natural step: it would change nothing")
    }

    func testAfterASharpTheCycleOffersANatural() {
        var b = bar([n(1), n(1)])
        b.upper[0].note.accidental = .sharp
        var seen: [SystemReading.Accidental] = []
        for _ in 0..<4 {
            b.cycleAccidental(.upper, 1)
            seen.append(b.upper[1].note.accidental)
        }
        XCTAssertEqual(seen, [.sharp, .flat, .natural, .none])
        XCTAssertEqual(b.midiPitches(.upper), [66, 66])
    }

    func testANaturalThatCancelsNothingCountsAsNone() {
        var b = bar([n(1), n(1)])
        b.upper[1].note.accidental = .natural
        XCTAssertEqual(b.shownAccidental(.upper, 1), .none)
        b.cycleAccidental(.upper, 1)
        XCTAssertEqual(b.upper[1].note.accidental, .sharp, "one click to a sharp")
        b.upper[0].note.accidental = .sharp
        b.upper[1].note.accidental = .natural
        XCTAssertEqual(b.shownAccidental(.upper, 1), .natural, "this one cancels the F♯")
    }

    func testDurationAndDotChangeTheBarsLength() {
        var b = bar([n(1), n(2), n(3)])
        XCTAssertEqual(b.quarters(.upper), 3)
        b.setDuration(.upper, 2, .half)
        XCTAssertEqual(b.quarters(.upper), 4)
        b.toggleDot(.upper, 0)
        XCTAssertEqual(b.quarters(.upper), 4.5)
    }

    func testNoteToRestAndBack() {
        var b = bar([n(1)])
        b.upper[0].note.accidental = .sharp
        b.upper[0].note.finger = 3
        b.toggleRest(.upper, 0)
        XCTAssertTrue(b.upper[0].note.rest)
        XCTAssertEqual(b.upper[0].note.accidental, .none)
        XCTAssertNil(b.upper[0].note.finger)
        XCTAssertEqual(b.midiPitches(.upper), [nil])
        b.toggleRest(.upper, 0)
        XCTAssertEqual(b.midiPitches(.upper), [65])
    }

    func testInsertCopiesItsNeighbourWithoutAccidentalOrFinger() {
        var b = bar([n(1, .half), n(4, .eighth)])
        b.upper[0].note.accidental = .sharp
        b.upper[0].note.finger = 2
        let at = b.insertNote(.upper, after: 0, clef: .treble)
        XCTAssertEqual(at, 1)
        XCTAssertEqual(b.upper.map(\.note.position), [1, 1, 4])
        XCTAssertEqual(b.upper[1].note.duration, .half)
        XCTAssertEqual(b.upper[1].note.accidental, .none)
        XCTAssertNil(b.upper[1].note.finger)
        XCTAssertEqual(b.insertNote(.upper, after: nil, clef: .treble), 0, "nil adds at the start")
    }

    func testInsertOnAnEmptyStaff() {
        var b = bar([])
        b.insertNote(.lower, after: nil, clef: .bass)
        XCTAssertEqual(b.lower.map(\.note.position), [4])
        XCTAssertEqual(b.lower[0].clef, .bass)
        XCTAssertEqual(b.lower[0].note.duration, .quarter)
    }

    func testDelete() {
        var b = bar([n(1), n(2)])
        b.deleteNote(.upper, 0)
        XCTAssertEqual(b.upper.map(\.note.position), [2])
        b.deleteNote(.upper, 5)
        XCTAssertEqual(b.upper.count, 1, "out of range is ignored")
        b.deleteNote(.upper, 0)
        XCTAssertTrue(b.upper.isEmpty)
        // An emptied staff is written as a bar's rest.
        let piece = ScoreWriter.write([b], title: "")
        XCTAssertTrue(piece.score.measures[0].events(onStaff: 0).allSatisfy(\.isMeasureRest))
    }

    func testClefChangeKeepsLinesAndSpaces() {
        var b = bar([n(4)])
        XCTAssertEqual(b.midiPitches(.upper), [71], "B4 in treble")
        b.setClef(.upper, .bass)
        XCTAssertEqual(b.upper[0].note.position, 4)
        XCTAssertEqual(b.midiPitches(.upper), [50], "D3 in bass")
        XCTAssertEqual(b.clef(.upper, fallback: .treble), .bass)
        XCTAssertEqual(b.clef(.lower, fallback: .bass), .bass, "an empty staff uses the fallback")
    }
}
