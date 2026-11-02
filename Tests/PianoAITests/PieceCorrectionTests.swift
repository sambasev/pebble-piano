import XCTest
@testable import PianoAI

final class PieceCorrectionTests: XCTestCase {
    func sample() -> PieceCorrection {
        let note = BarMerge.Note(note: .init(position: 4, duration: .half, dotted: true, accidental: .sharp, finger: 3),
                                 clef: .bass,
                                 head: .init(x: 40, y: 30, position: 4, offset: 0.1, filled: false, pitch: "D3"))
        let bar = BarMerge.Bar(upper: [note], lower: [], upperStatus: .corrected(1),
                               lowerStatus: .flagged(.noteCountDiffers(found: 2, read: 0)), pageBar: 0)
        var nudged = bar
        nudged.upper[0].note.position = 5
        let geometry = NoteheadGeometry.System(upper: .init(lines: [10, 20, 30, 40, 50], spacing: 10),
                                               lower: .init(lines: [110, 120, 130, 140, 150], spacing: 10),
                                               upperHeads: [note.head!], lowerHeads: [], barEdges: [0, 100])
        let reading = SystemReading(measureCount: 1, measures: [.init(upper: .init(clef: .bass, notes: [note.note]),
                                                                      lower: .init(clef: .bass, notes: []))])
        return PieceCorrection(oneStaff: true,
                               lines: [.init(found: FoundSystem(index: 3, left: 1, top: 2, right: 300, bottom: 200, spacing: 9.5),
                                             singleStaff: true, reading: reading, geometry: geometry)],
                               bars: [.init(line: 0, bar: nudged, original: bar, resolution: .nudged)])
    }

    func testRoundTrips() throws {
        let original = sample()
        let decoded = try JSONDecoder().decode(PieceCorrection.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.isConsistent)
    }

    func testABarOnAMissingLineIsInconsistent() {
        var c = sample()
        c.bars[0].line = 1
        XCTAssertFalse(c.isConsistent)
    }

    func testANewerVersionIsNotUsed() {
        var c = sample()
        c.version = PieceCorrection.currentVersion + 1
        XCTAssertFalse(c.isConsistent)
    }
}
