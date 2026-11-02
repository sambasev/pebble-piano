import XCTest
@testable import PianoAI

final class SystemReadingTests: XCTestCase {
    func testStaffPositionsToPitch() {
        XCTAssertEqual(StaffPitch.name(clef: .treble, position: 0), "E4")
        XCTAssertEqual(StaffPitch.name(clef: .treble, position: -2), "C4")
        XCTAssertEqual(StaffPitch.name(clef: .treble, position: 5), "C5")
        XCTAssertEqual(StaffPitch.name(clef: .treble, position: 9), "G5")
        XCTAssertEqual(StaffPitch.name(clef: .bass, position: 0), "G2")
        XCTAssertEqual(StaffPitch.name(clef: .bass, position: 8), "A3")
        XCTAssertEqual(StaffPitch.midi(clef: .treble, position: -2), 60)
        XCTAssertEqual(StaffPitch.midi(clef: .treble, position: 3, accidental: .sharp), 70)  // A#4
        XCTAssertEqual(StaffPitch.midi(clef: .bass, position: 10), 60)  // middle C above the bass staff
    }

    func testChosenClefsReplaceTheReadOnesAndChangeThePitches() {
        let note = SystemReading.Note(position: 0, duration: .quarter)
        let read = SystemReading(measureCount: 2, measures: Array(repeating: SystemReading.Measure(
            upper: .init(clef: .treble, notes: [note]), lower: .init(clef: .treble, notes: [note])), count: 2))
        let chosen = read.withClefs(upper: .treble, lower: .bass)
        XCTAssertEqual(chosen.measures.map(\.lower.clef), [.bass, .bass])
        XCTAssertEqual(chosen.measures.map(\.upper.clef), [.treble, .treble])
        XCTAssertEqual(chosen.measures[0].lower.notes, [note])
        let bar = BarMerge.merge(chosen, NoteheadGeometry.System(
            upper: .init(lines: [0, 10, 20, 30, 40], spacing: 10), lower: .init(lines: [80, 90, 100, 110, 120], spacing: 10),
            upperHeads: [], lowerHeads: [], barEdges: [0, 100, 200]))
        XCTAssertEqual(bar.first?.lower.first?.name, "G2")
    }

    func testDecodesSavedReading() throws {
        let r = try BeyerFixtures.reading("no12", .scan)
        XCTAssertEqual(r.measures.count, 8)
        XCTAssertEqual(r.measures[0].upper.clef, .treble)
        XCTAssertEqual(r.measures[0].upper.notes.count, 4)
        XCTAssertEqual(r.measures[0].upper.notes[0].durationName, "quarter")
        XCTAssertEqual(r.measures[0].lower.notes[0].quarters, 4)
    }

    func testSchemaIsStrictAndPromptMentionsPositions() {
        XCTAssertEqual(SystemReader.schema["additionalProperties"], false)
        XCTAssertEqual(SystemReader.schema["required"], ["measureCount", "measures"])
        XCTAssertTrue(SystemReader.prompt.contains("-2 = first ledger line below"))
    }
}
