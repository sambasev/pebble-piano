import XCTest
@testable import PianoAI

/// A sharp, flat or natural lasts to the end of the bar on its own line or space, in what a
/// piece plays (MIDI, Listen) and in how the review card names its notes.
final class BarAccidentalsTests: XCTestCase {
    /// Treble staff: position 1 is F4, 8 is F5, 3 is A4.
    func n(_ position: Int, _ accidental: SystemReading.Accidental = .none) -> BarMerge.Note {
        BarMerge.Note(note: .init(position: position, duration: .quarter, accidental: accidental), clef: .treble)
    }

    func bar(_ upper: [BarMerge.Note]) -> BarMerge.Bar {
        BarMerge.Bar(upper: upper, lower: [], upperStatus: .confirmed, lowerStatus: .confirmed, pageBar: 0)
    }

    func testASharpCarriesToLaterNotesOnTheSameLine() {
        XCTAssertEqual(bar([n(1, .sharp), n(1), n(1)]).midiPitches(.upper), [66, 66, 66])
    }

    func testANaturalCancelsIt() {
        XCTAssertEqual(bar([n(1, .sharp), n(1, .natural), n(1)]).midiPitches(.upper), [66, 65, 65])
    }

    func testOnlyThatOctaveAndThatLetter() {
        // F♯4, then F5 and A4 are untouched.
        XCTAssertEqual(bar([n(1, .sharp), n(8), n(3)]).midiPitches(.upper), [66, 77, 69])
    }

    func testAFlatCarriesToo() {
        XCTAssertEqual(bar([n(3, .flat), n(3)]).midiPitches(.upper), [68, 68])
    }

    func testRestsAreNil() {
        let rest = BarMerge.Note(note: .init(rest: true, position: 4, duration: .quarter), clef: .treble)
        XCTAssertEqual(bar([n(1, .sharp), rest, n(1)]).midiPitches(.upper), [66, nil, 66])
    }

    func testTheNextBarStartsAfresh() {
        let piece = ScoreWriter.write([bar([n(1, .sharp), n(1)]), bar([n(1), n(1)])], title: "")
        let pitches = piece.score.measures.map { $0.events(onStaff: 0).compactMap { $0.notes.first?.midi } }
        XCTAssertEqual(pitches, [[66, 66], [65, 65]])
    }

    func testTheWrittenPieceCarriesItInSpellingAndMIDI() {
        let piece = ScoreWriter.write([bar([n(1, .sharp), n(1)])], title: "")
        let notes = piece.score.measures[0].events(onStaff: 0).compactMap(\.notes.first)
        XCTAssertEqual(notes.map(\.midi), [66, 66])
        XCTAssertEqual(notes.map(\.spelled.alter), [1, 1], "the second F is spelled F♯")
        XCTAssertEqual(notes.map(\.accidental), [1, nil], "but only the first prints its sharp")
    }

    func testANoteNamesItsOwnAccidental() {
        XCTAssertEqual(n(-2, .sharp).name, "C♯4")
        XCTAssertEqual(n(3, .flat).name, "A♭4")
        XCTAssertEqual(n(1).name, "F4")
        XCTAssertEqual(n(1, .natural).name, "F4", "readings often mark plain notes natural")
    }

    func testTheReviewCardNamesNotesAsTheySound() {
        XCTAssertEqual(bar([n(1, .sharp), n(1), n(1, .natural), n(8)]).noteNames(.upper), ["F♯4", "F♯4", "F♮4", "F5"])
        XCTAssertEqual(bar([n(1, .natural), n(3, .natural)]).noteNames(.upper), ["F4", "A4"], "a natural that cancels nothing")
    }
}
