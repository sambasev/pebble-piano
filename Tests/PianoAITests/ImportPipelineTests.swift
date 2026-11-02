#if canImport(PDFKit)
import PDFKit
#endif
import XCTest
import PianoGraderCore
@testable import PianoAI

final class ImportPipelineTests: XCTestCase {
    func page(_ name: String) throws -> Gray {
        let data = try Data(contentsOf: BeyerFixtures.root.appendingPathComponent("\(name).png"))
        return try XCTUnwrap(Gray.decode(data))
    }

    func testFindsTheSystemsOnBeyerPages() throws {
        // Page 24: Nos. 12, 13, 14 and two systems of No. 15. Page 27: the end of No. 22,
        // then two systems each of Nos. 23, 24 and 25.
        XCTAssertEqual(SystemFinder.find(in: try page("op101-p24")).count, 5)
        XCTAssertEqual(SystemFinder.find(in: try page("op101-p27")).count, 7)
    }

    #if canImport(PDFKit)
    func testPagesOfTextHaveNoSystems() throws {
        // Pages 2 and 3 of the bundled Beyer are the preface, in German, English and French:
        // evenly spaced lines of text, which were taken for staves.
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let pdf = try XCTUnwrap(PDFDocument(url: repo.appendingPathComponent("Books/F_Beyer-Op101.pdf")))
        for index in [1, 2] {
            XCTAssertEqual(try XCTUnwrap(BookImporter.page(pdf, index: index)).systems.count, 0, "page \(index + 1)")
        }
        XCTAssertEqual(try XCTUnwrap(BookImporter.page(pdf, index: 3)).systems.count, 2)
    }
    #endif

    func testSystemsDontOverlapAndCropToPNG() throws {
        let p = try page("op101-p27")
        let systems = SystemFinder.find(in: p)
        for (a, b) in zip(systems, systems.dropFirst()) { XCTAssertLessThanOrEqual(a.bottom, b.top) }
        let png = try XCTUnwrap(SystemFinder.crop(p, systems[3]).pngData())
        let back = try XCTUnwrap(Gray.decode(png))
        XCTAssertEqual(back.width, systems[3].width)
        XCTAssertEqual(back.height, systems[3].height)
    }

    func testAFoundSystemMeasuresLikeTheFixtureCrop() throws {
        // Kinderlied's first system is the fourth on page 27 (150 dpi here, 220 in the fixture).
        let p = try page("op101-p27")
        let system = SystemFinder.find(in: p)[3]
        let png = try XCTUnwrap(SystemFinder.crop(p, system).pngData())
        let measured = try NoteheadGeometry.measure(png: png)
        XCTAssertEqual(measured.barCount, 6)
        let merged = BarMerge.merge(try BeyerFixtures.reading("no24a", .scan), measured)
        XCTAssertGreaterThanOrEqual(merged.filter { $0.upperStatus.isTrusted && $0.lowerStatus.isTrusted }.count, 3)
    }

    func testScoreAndMIDIFromMergedBars() throws {
        let reading = try BeyerFixtures.reading("no12", .modern)
        let bars = BarMerge.merge(reading, try NoteheadGeometry.measure(png: try BeyerFixtures.image("no12", .modern)))
        let piece = ScoreWriter.write(bars, title: "Beyer No. 12")

        XCTAssertEqual(piece.score.timeSignature, TimeSignature(numerator: 4, denominator: 4))
        XCTAssertEqual(piece.score.staves, [.treble, .treble])
        XCTAssertEqual(piece.score.measures.count, 8)
        XCTAssertEqual(piece.score.measures[1].startSixteenth, 16)
        XCTAssertEqual(piece.score.measures[0].events(onStaff: 0).map { $0.notes.first?.midi }, [72, 74, 76, 77])
        XCTAssertEqual(piece.score.measures[0].events(onStaff: 1).first?.type, .whole)
        XCTAssertEqual(piece.fingering.count, 29)
        XCTAssertTrue(piece.musicXML.contains("<staves>2</staves>"))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("beyer12-\(UUID()).mid")
        try piece.midi.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let sequence = try MIDIFile.read(url: url)
        XCTAssertEqual(sequence.notes.count, 38)
        XCTAssertEqual(Set(sequence.notes.map(\.track)), [0, 1])
        XCTAssertEqual(sequence.notes.filter { $0.track == 1 }.first?.pitch, 60)
    }

    func testOddBarLengthsGetACommonMetre() {
        func bar(_ durations: [SystemReading.Duration]) -> BarMerge.Bar {
            let notes = durations.map { BarMerge.Note(note: SystemReading.Note(position: 4, duration: $0), clef: .treble) }
            return BarMerge.Bar(upper: notes, lower: [], upperStatus: .confirmed, lowerStatus: .confirmed, pageBar: 0)
        }
        // A worksheet line with no barlines: eight half notes and a quarter read as one bar of 17/4.
        let worksheet = bar(Array(repeating: .half, count: 8) + [.quarter])
        let piece = ScoreWriter.write([worksheet], title: "")
        XCTAssertEqual(piece.score.timeSignature, TimeSignature(numerator: 4, denominator: 4))
        XCTAssertEqual(piece.score.measures[0].length, 68)  // the bar keeps every note

        // A misread bar doesn't outvote the common metre around it.
        let waltz = Array(repeating: bar([.half, .quarter]), count: 3) + [bar([.half, .half, .quarter])]
        XCTAssertEqual(ScoreWriter.timeSignature(of: waltz), TimeSignature(numerator: 3, denominator: 4))
        XCTAssertEqual(ScoreWriter.timeSignature(of: [bar([.eighth, .eighth, .eighth])]), TimeSignature(numerator: 3, denominator: 8))
        XCTAssertEqual(ScoreWriter.timeSignature(of: [bar([.half, .half, .quarter])]), TimeSignature(numerator: 5, denominator: 4))
        XCTAssertEqual(ScoreWriter.timeSignature(of: [bar([.quarter, .quarter, .eighth])]), TimeSignature(numerator: 5, denominator: 8))
        XCTAssertEqual(ScoreWriter.timeSignature(of: [bar([.quarter, .quarter, .quarter, .eighth])]),
                       TimeSignature(numerator: 7, denominator: 8))
        // Six eighths: 6/8 when the notes fall in threes, 3/4 when in twos.
        XCTAssertEqual(ScoreWriter.timeSignature(of: [bar([.quarter, .eighth, .quarter, .eighth])]),
                       TimeSignature(numerator: 6, denominator: 8))
        XCTAssertEqual(ScoreWriter.timeSignature(of: [bar([.quarter, .quarter, .quarter])]), TimeSignature(numerator: 3, denominator: 4))
    }
}
