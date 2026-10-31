import XCTest
@testable import PianoAI

/// Model reading + measured pitch on the Beyer fixtures, scored against the verified answer
/// key: the same test as `scripts/ai_probe3.py`. No API calls (the readings are saved).
final class NoteheadGeometryTests: XCTestCase {
    struct Score { var model = 0, merged = 0, notes = 0, trusted = 0, staffBars = 0, silent = 0 }

    func score(_ source: BeyerFixtures.Source) throws -> Score {
        let truth = try BeyerFixtures.truth()
        var s = Score()
        for (piece, crops) in BeyerFixtures.pieces {
            var bars: [BarMerge.Bar] = []
            var model: [SystemReading.Measure] = []
            for crop in crops {
                let reading = try BeyerFixtures.reading(crop, source)
                let system = try NoteheadGeometry.measure(png: try BeyerFixtures.image(crop, source))
                bars += BarMerge.merge(reading, system)
                model += reading.measures
            }
            let key = try XCTUnwrap(truth[piece]).measures
            for (i, want) in key.enumerated() {
                for staff in SystemReading.StaffName.allCases {
                    let expected = want[staff.rawValue] ?? []
                    let got = i < bars.count ? bars[i].notes(staff).map { [$0.name, $0.note.durationName] } : []
                    let modelStaff = i < model.count ? model[i][staff] : SystemReading.Staff(clef: .treble, notes: [])
                    let raw = modelStaff.notes.map { [$0.rest ? "r" : StaffPitch.name(clef: modelStaff.clef, position: $0.position), $0.durationName] }
                    s.notes += expected.count
                    s.staffBars += 1
                    for (j, e) in expected.enumerated() {
                        if j < got.count && got[j] == e { s.merged += 1 }
                        if j < raw.count && raw[j] == e { s.model += 1 }
                    }
                    if i < bars.count, bars[i].status(staff).isTrusted {
                        s.trusted += 1
                        if got != expected {
                            s.silent += 1
                            print("SILENT ERROR \(source) \(piece) bar \(i + 1) \(staff): \(got) vs \(expected)")
                        }
                    } else if i < bars.count {
                        print("flagged \(source) \(piece) bar \(i + 1) \(staff): \(bars[i].status(staff))")
                    }
                }
            }
        }
        print("\(source): model alone \(s.model)/\(s.notes), with measured pitch \(s.merged)/\(s.notes); "
              + "trusted \(s.trusted)/\(s.staffBars); silent errors \(s.silent)")
        return s
    }

    /// The probe: 150/155 on the scan, 155/155 on the modern engraving, no silent errors.
    func testScanMergeMatchesProbe() throws {
        let s = try score(.scan)
        XCTAssertEqual(s.silent, 0, "a wrong note in a trusted bar")
        XCTAssertGreaterThanOrEqual(Double(s.merged) / Double(s.notes), 0.93)
        XCTAssertGreaterThanOrEqual(s.trusted, 38)
    }

    func testModernMergeMatchesProbe() throws {
        let s = try score(.modern)
        XCTAssertEqual(s.silent, 0, "a wrong note in a trusted bar")
        XCTAssertGreaterThanOrEqual(Double(s.merged) / Double(s.notes), 0.98)
        XCTAssertGreaterThanOrEqual(s.trusted, 40)
    }

    func testFindsTwoStavesAndBarsOnEveryCrop() throws {
        for source in BeyerFixtures.Source.allCases {
            for (crop, bars) in [("no12", 8), ("no13", 8), ("no24a", 6), ("no24b", 6)] {
                let system = try NoteheadGeometry.measure(png: try BeyerFixtures.image(crop, source))
                XCTAssertEqual(system.barCount, bars, "\(source) \(crop) bar edges \(system.barEdges.map { Int($0) })")
                XCTAssertEqual(system.upper.spacing, system.lower.spacing, accuracy: 1.5)
            }
        }
    }

    func testFirstNotesOfAContinuationSystemAreMeasured() throws {
        // Kinderlied's second system has no time signature: its first E and C must not be
        // mistaken for one and skipped.
        let system = try NoteheadGeometry.measure(png: try BeyerFixtures.image("no24b", .scan))
        let firstBar = system.barEdges[0]..<system.barEdges[1]
        XCTAssertEqual(system.upperHeads.filter { firstBar.contains($0.x) }.first?.pitch, "E5")
        XCTAssertEqual(system.lowerHeads.filter { firstBar.contains($0.x) }.first?.pitch, "C4")
    }
}
