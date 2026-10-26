import XCTest
@testable import PianoGraderCore

final class MeasureSliceTests: XCTestCase {
    /// Four bars of 4/4 at 120 bpm: one half note per half bar, pitches 60, 62, 64, …
    private func song() -> MIDISequence {
        let notes = (0..<8).map { i -> NoteEvent in
            let beats = Double(i) * 2
            return NoteEvent(pitch: 60 + i * 2, onset: beats * 0.5, offset: (beats + 2) * 0.5,
                             onsetBeats: beats, offsetBeats: beats + 2)
        }
        return MIDISequence(notes: notes, initialTempoBPM: 120)
    }

    func testMeasureCount() {
        XCTAssertEqual(song().measureCount, 4)
        XCTAssertEqual(MIDISequence(notes: []).measureCount, 0)
    }

    func testOneMeasureMovesToTheStart() {
        let bar = song().measures(3...3)
        XCTAssertEqual(bar.notes.map(\.pitch), [68, 70])
        XCTAssertEqual(bar.notes.map(\.onsetBeats), [0, 2])
        XCTAssertEqual(bar.notes.map(\.onset), [0, 1])
        XCTAssertEqual(bar.notes.last?.offsetBeats, 4)
        XCTAssertEqual(bar.measureCount, 1)
        XCTAssertEqual(bar.initialTempoBPM, 120)
    }

    func testRangeOfMeasures() {
        let bars = song().measures(2...3)
        XCTAssertEqual(bars.notes.map(\.pitch), [64, 66, 68, 70])
        XCTAssertEqual(bars.notes.first?.onsetBeats, 0)
        XCTAssertEqual(bars.measureCount, 2)
    }

    func testHeldNoteIsCutAtTheEnd() {
        let long = MIDISequence(notes: [NoteEvent(pitch: 60, onset: 0, offset: 4, onsetBeats: 0, offsetBeats: 8)],
                                initialTempoBPM: 120)
        let first = long.measures(1...1)
        XCTAssertEqual(first.notes.first?.offsetBeats, 4)
        XCTAssertEqual(first.notes.first?.offset, 2)
    }

    func testOutOfRangeIsEmpty() {
        XCTAssertTrue(song().measures(9...9).notes.isEmpty)
    }
}
