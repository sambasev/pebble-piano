import XCTest
@testable import PianoGraderCore
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A note `length` quarters long starting `start` quarters in, at 120 bpm.
private func note(_ pitch: Int, _ start: Double, _ length: Double, track: Int = 0, channel: Int = 0) -> NoteEvent {
    NoteEvent(pitch: pitch, onset: start * 0.5, offset: (start + length) * 0.5, velocity: 80, channel: channel, track: track)
}

/// Writes notes to MIDI and reads them back, the way a file opened in PianoPad arrives.
private func sequence(_ notes: [NoteEvent], ts: TimeSignature = .common, key: KeySignature? = nil) throws -> MIDISequence {
    try MIDIFile.parse(MIDIFile.write(notes: notes, timeSignature: ts, keySignature: key))
}

final class SpellingTests: XCTestCase {
    func testSpellingFollowsTheKey() {
        XCTAssertEqual(KeySignature.cMajor.spell(61).name, "C♯4")
        XCTAssertEqual(KeySignature(fifths: -1).spell(70).name, "B♭4")
        XCTAssertEqual(KeySignature(fifths: -1).spell(71).name, "B4")       // natural, not C♭
        XCTAssertEqual(KeySignature(fifths: 1).spell(77).name, "F5")        // F natural in G major
        XCTAssertEqual(KeySignature(fifths: 1).spell(78).name, "F♯5")
        XCTAssertEqual(KeySignature(fifths: -3).spell(63).name, "E♭4")
        XCTAssertEqual(KeySignature(fifths: -3).spell(66).name, "G♭4")      // flats in flat keys
        XCTAssertEqual(KeySignature(fifths: 2).spell(70).name, "A♯4")       // sharps in sharp keys
    }

    func testSpellingKeepsTheLettersOctave() {
        let bSharp = KeySignature(fifths: 7).spell(60)
        XCTAssertEqual(bSharp.name, "B♯3")
        XCTAssertEqual(bSharp.midi, 60)
        let cFlat = KeySignature(fifths: -7).spell(59)
        XCTAssertEqual(cFlat.name, "C♭4")
        XCTAssertEqual(cFlat.midi, 59)
    }

    func testKeySignatureAlterations() {
        let d = KeySignature(fifths: 2) // F♯ C♯
        XCTAssertEqual((0..<7).map { d.alter(forStep: $0) }, [1, 0, 0, 1, 0, 0, 0])
        let eFlat = KeySignature(fifths: -3) // B♭ E♭ A♭
        XCTAssertEqual((0..<7).map { eFlat.alter(forStep: $0) }, [0, 0, -1, 0, 0, -1, -1])
    }

    func testKeyEstimate() {
        let gMajor = [67, 69, 71, 72, 74, 76, 78, 79].enumerated().map { note($0.element, Double($0.offset), 1) }
        XCTAssertEqual(KeySignature.estimate(from: gMajor).fifths, 1)
        let fMajor = [65, 67, 69, 70, 72, 74, 76, 77].enumerated().map { note($0.element, Double($0.offset), 1) }
        XCTAssertEqual(KeySignature.estimate(from: fMajor).fifths, -1)
        let cMajor = [60, 62, 64, 65, 67].enumerated().map { note($0.element, Double($0.offset), 1) }
        XCTAssertEqual(KeySignature.estimate(from: cMajor).fifths, 0)
    }
}

final class TranscriberTests: XCTestCase {
    func testReadsTracksKeyAndEndBeats() throws {
        let seq = try sequence([note(72, 0, 1.5, track: 0), note(48, 0, 4, track: 1)],
                               ts: TimeSignature(numerator: 3, denominator: 4), key: KeySignature(fifths: -2, isMinor: true))
        XCTAssertEqual(seq.keySignature, KeySignature(fifths: -2, isMinor: true))
        XCTAssertEqual(Set(seq.notes.map(\.track)), [0, 1])
        let high = try XCTUnwrap(seq.notes.first { $0.pitch == 72 })
        XCTAssertEqual(high.offsetBeats ?? 0, 1.5, accuracy: 1e-9)
    }

    /// Two hands in G major 3/4: dotted rhythm, sixteenths, a tie over the barline, an
    /// accidental cancelled later in the measure, a chord and rests.
    private func minuet() throws -> Score {
        let rh = [
            note(74, 0, 1.5), note(72, 1.5, 0.5), note(71, 2, 1),
            note(67, 3, 0.25), note(69, 3.25, 0.25), note(71, 3.5, 0.25), note(72, 3.75, 0.25), note(74, 4, 3),
            note(77, 7, 0.5), note(78, 7.5, 0.5), note(79, 8, 1),
            note(67, 10, 2), note(71, 10, 2), note(74, 10, 2),
        ]
        let lh = [note(43, 0, 3, track: 1), note(50, 0, 3, track: 1), note(47, 3, 3, track: 1),
                  note(48, 6, 1, track: 1), note(50, 7, 1, track: 1), note(38, 8, 1, track: 1), note(43, 9, 3, track: 1)]
        let seq = try sequence(rh + lh, ts: TimeSignature(numerator: 3, denominator: 4), key: KeySignature(fifths: 1))
        return Transcriber().transcribe(seq, title: "Minuet")
    }

    func testTwoTracksBecomeTwoStaves() throws {
        let score = try minuet()
        XCTAssertEqual(score.staves, [.treble, .bass])
        XCTAssertEqual(score.key.fifths, 1)
        XCTAssertEqual(score.measures.count, 4)
        XCTAssertTrue(score.measures.allSatisfy { $0.length == 12 })
        // Right hand stays on the top staff, left hand on the bottom.
        for m in score.measures {
            for e in m.events where !e.isRest {
                XCTAssertTrue(e.notes.allSatisfy { e.staff == 0 ? $0.midi >= 67 : $0.midi <= 50 }, "measure \(m.number)")
            }
        }
    }

    func testRhythmsTiesAndRests() throws {
        let score = try minuet()
        let m1 = score.measures[0].events(onStaff: 0)
        XCTAssertEqual(m1.map(\.type), [.quarter, .eighth, .quarter])
        XCTAssertEqual(m1.map(\.dots), [1, 0, 0])

        // D5 held 3 quarters from beat 2 of measure 2: a half tied to a quarter.
        let m2 = score.measures[1].events(onStaff: 0)
        XCTAssertEqual(m2.map(\.type), [.sixteenth, .sixteenth, .sixteenth, .sixteenth, .half])
        XCTAssertEqual(m2.last?.notes.first?.tieStart, true)
        let m3 = score.measures[2].events(onStaff: 0)
        XCTAssertEqual(m3.first?.notes.first?.tieStop, true)
        XCTAssertEqual(m3.first?.notes.first?.midi, 74)

        let m4 = score.measures[3].events(onStaff: 0)
        XCTAssertTrue(m4[0].isRest)
        XCTAssertEqual(m4[0].type, .quarter)
        XCTAssertEqual(m4[1].notes.map(\.midi), [67, 71, 74])
        XCTAssertEqual(m4[1].type, .half)
    }

    func testEachStaffFillsEveryMeasure() throws {
        let score = try minuet()
        for m in score.measures {
            for staff in score.staves.indices {
                let events = m.events(onStaff: staff)
                XCTAssertEqual(events.reduce(0) { $0 + $1.duration }, m.length, "measure \(m.number) staff \(staff)")
                var position = 0
                for e in events {
                    XCTAssertEqual(e.start, position)
                    position += e.duration
                }
            }
        }
    }

    func testAccidentalsWithinAMeasure() throws {
        let score = try minuet()
        let m3 = score.measures[2].events(onStaff: 0)
        let fNatural = try XCTUnwrap(m3.first { $0.notes.first?.midi == 77 })
        XCTAssertEqual(fNatural.notes[0].spelled.name, "F5")
        XCTAssertEqual(fNatural.notes[0].accidental, 0)      // ♮ against the key's F♯
        let fSharp = try XCTUnwrap(m3.first { $0.notes.first?.midi == 78 })
        XCTAssertEqual(fSharp.notes[0].accidental, 1)        // ♯ again after the natural
        let g = try XCTUnwrap(m3.first { $0.notes.first?.midi == 79 })
        XCTAssertNil(g.notes[0].accidental)
        // The tied D5 at the start of the measure prints nothing.
        XCTAssertNil(m3[0].notes[0].accidental)
    }

    func testBeams() throws {
        let score = try minuet()
        let sixteenths = score.measures[1].events(onStaff: 0).prefix(4)
        XCTAssertEqual(sixteenths.map { $0.beams }, [[.begin, .begin], [.continue, .continue], [.continue, .continue], [.end, .end]])
        let eighths = score.measures[2].events(onStaff: 0).filter { $0.type == .eighth }
        XCTAssertEqual(eighths.map { $0.beams }, [[.begin], [.end]])
        // The lone eighth in measure 1 (after a dotted quarter) is not beamed.
        XCTAssertEqual(score.measures[0].events(onStaff: 0)[1].beams, [])
    }

    func testSingleTrackSplitsByPitchAndSkipsDrums() throws {
        let notes = [note(48, 0, 1), note(64, 0, 1), note(67, 0, 1), note(50, 1, 1), note(65, 1, 1),
                     note(36, 0, 0.25, channel: 9)]
        let score = Transcriber().transcribe(try sequence(notes))
        XCTAssertEqual(score.staves, [.treble, .bass])
        let top = score.measures[0].events(onStaff: 0)
        let bottom = score.measures[0].events(onStaff: 1)
        XCTAssertEqual(top[0].notes.map(\.midi), [64, 67])
        XCTAssertEqual(bottom[0].notes.map(\.midi), [48])
        XCTAssertFalse(score.measures.flatMap(\.events).flatMap(\.notes).contains { $0.midi == 36 })
    }

    func testOneClefWhenTheMusicFits() throws {
        let rh = Transcriber().transcribe(try sequence([60, 62, 64, 65, 67].enumerated().map { note($0.element, Double($0.offset), 1) }))
        XCTAssertEqual(rh.staves, [.treble])
        let lh = Transcriber().transcribe(try sequence([43, 45, 47, 48].enumerated().map { note($0.element, Double($0.offset), 1) }))
        XCTAssertEqual(lh.staves, [.bass])
    }

    func testOnsetsSnapToTheSixteenthGrid() throws {
        // Slightly early and late notes, as from a played-in file.
        let notes = [note(60, 0.03, 0.95), note(62, 0.98, 1.0), note(64, 2.04, 0.5), note(65, 2.49, 0.5)]
        let score = Transcriber().transcribe(try sequence(notes))
        let events = score.measures[0].events(onStaff: 0).filter { !$0.isRest }
        XCTAssertEqual(events.map(\.start), [0, 4, 8, 10])
        XCTAssertEqual(events.map(\.type), [.quarter, .quarter, .eighth, .eighth])
    }

    func testLongNotesSplitOnReadablePositions() {
        // A half note starting on the "and" of beat 1 is written eighth + quarter + eighth, tied.
        let pieces = Transcriber.split(start: 2, length: 8)
        XCTAssertEqual(pieces.map(\.start), [2, 8])
        XCTAssertEqual(pieces.map(\.length), [6, 2])
        XCTAssertEqual(Transcriber.split(start: 0, length: 5).map(\.length), [4, 1])
        XCTAssertEqual(Transcriber.split(start: 0, length: 16).map(\.length), [16])
    }

    func testEmptySequenceGivesOneRestMeasure() {
        let score = Transcriber().transcribe(MIDISequence(notes: []))
        XCTAssertEqual(score.measures.count, 1)
        XCTAssertTrue(score.measures[0].events[0].isMeasureRest)
    }

    func testMeasureAtQuarter() throws {
        let score = try minuet()
        XCTAssertEqual(score.measureIndex(atQuarter: 0), 0)
        XCTAssertEqual(score.measureIndex(atQuarter: 3), 1)
        XCTAssertEqual(score.measureIndex(atQuarter: 11.8), 3)
        XCTAssertNil(score.measureIndex(atQuarter: 12))
    }
}

final class MusicXMLTests: XCTestCase {
    /// Collects per-measure, per-staff note durations and a few element counts.
    private final class Collector: NSObject, XMLParserDelegate {
        var path: [String] = []
        var text = ""
        var measure = 0
        var counts: [String: Int] = [:]
        var inNote = false, isChord = false, duration = 0, staff = 1
        var filled: [Int: [Int: Int]] = [:] // measure → staff → sixteenths
        var backups: [Int] = []
        var attributes: [String: [String: String]] = [:]

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            path.append(name)
            text = ""
            counts[name, default: 0] += 1
            switch name {
            case "measure": measure = Int(a["number"] ?? "0") ?? 0
            case "note": inNote = true; isChord = false; duration = 0; staff = 1
            case "chord": isChord = true
            default: break
            }
            if !a.isEmpty { attributes[name] = a }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "duration" where inNote: duration = Int(value) ?? 0
            case "duration" where path.dropLast().last == "backup": backups.append(Int(value) ?? 0)
            case "staff" where inNote: staff = Int(value) ?? 1
            case "note":
                if !isChord { filled[measure, default: [:]][staff, default: 0] += duration }
                inNote = false
            default: break
            }
            path.removeLast()
            text = ""
        }
    }

    private func parse(_ xml: String) throws -> Collector {
        let parser = XMLParser(data: Data(xml.utf8))
        let collector = Collector()
        parser.delegate = collector
        XCTAssertTrue(parser.parse(), "\(parser.parserError.map { "\($0)" } ?? "parse failed")")
        return collector
    }

    private func minuetScore() throws -> Score {
        let rh = [note(74, 0, 1.5), note(72, 1.5, 0.5), note(71, 2, 1), note(74, 3, 4), note(77, 7, 0.5), note(78, 7.5, 0.5),
                  note(79, 8, 1), note(67, 10, 2), note(71, 10, 2)]
        let lh = [note(43, 0, 3, track: 1), note(47, 3, 3, track: 1), note(43, 6, 6, track: 1)]
        return Transcriber().transcribe(try sequence(rh + lh, ts: TimeSignature(numerator: 3, denominator: 4), key: KeySignature(fifths: 1)),
                                        title: "Minuet & Trio")
    }

    func testWellFormedAndEveryMeasureAddsUp() throws {
        let score = try minuetScore()
        let c = try parse(MusicXMLWriter.write(score))
        XCTAssertEqual(c.counts["measure"], score.measures.count)
        XCTAssertEqual(c.counts["part"], 1)
        // Divisions are sixteenths, so a 3/4 measure is 12 on each staff.
        for (number, staves) in c.filled {
            XCTAssertEqual(staves[1], 12, "measure \(number) staff 1")
            XCTAssertEqual(staves[2], 12, "measure \(number) staff 2")
        }
        XCTAssertEqual(c.backups, Array(repeating: 12, count: score.measures.count))
    }

    func testHeaderAndNotations() throws {
        let xml = MusicXMLWriter.write(try minuetScore())
        XCTAssertTrue(xml.contains("<work-title>Minuet &amp; Trio</work-title>"))
        XCTAssertTrue(xml.contains("<divisions>4</divisions>"))
        XCTAssertTrue(xml.contains("<fifths>1</fifths>"))
        XCTAssertTrue(xml.contains("<beats>3</beats>"))
        XCTAssertTrue(xml.contains("<staves>2</staves>"))
        XCTAssertTrue(xml.contains("<sign>F</sign>"))
        XCTAssertTrue(xml.contains("<tie type=\"start\"/>"))
        XCTAssertTrue(xml.contains("<tied type=\"stop\"/>"))
        XCTAssertTrue(xml.contains("<accidental>natural</accidental>"))
        XCTAssertTrue(xml.contains("<accidental>sharp</accidental>"))
        XCTAssertTrue(xml.contains("<beam number=\"1\">begin</beam>"))
        XCTAssertTrue(xml.contains("<chord/>"))
        XCTAssertTrue(xml.contains("<bar-style>light-heavy</bar-style>"))
        XCTAssertTrue(xml.contains("<sound tempo=\"120\"/>"))
    }

    func testSingleStaffHasNoStaffNumbers() throws {
        let score = Transcriber().transcribe(try sequence([60, 62, 64, 65].enumerated().map { note($0.element, Double($0.offset), 1) }))
        let xml = MusicXMLWriter.write(score)
        XCTAssertFalse(xml.contains("<staff>"))
        XCTAssertFalse(xml.contains("<backup>"))
        XCTAssertFalse(xml.contains("<staves>"))
    }
}

final class ScoreLayoutTests: XCTestCase {
    private func longScore() throws -> Score {
        let notes = (0..<64).map { i in note(60 + (i % 8), Double(i) * 0.5, 0.5) } + [note(43, 0, 32, track: 1)]
        return Transcriber().transcribe(try sequence(notes))
    }

    func testWrapsIntoSystemsThatFitTheWidth() throws {
        let score = try longScore()
        let layout = ScoreLayout(score: score, width: 600)
        XCTAssertGreaterThan(layout.systems.count, 1)
        XCTAssertEqual(layout.systems.flatMap { $0.measures.map(\.index) }, Array(score.measures.indices))
        for system in layout.systems {
            XCTAssertLessThanOrEqual(system.width, 600 + 0.5)
            XCTAssertEqual(system.staffTops.count, 2)
        }
        // Systems stack downwards without overlapping.
        for (a, b) in zip(layout.systems, layout.systems.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.top, a.top + a.height)
        }
        XCTAssertTrue(layout.systems[0].showsTimeSignature)
        XCTAssertFalse(layout.systems[1].showsTimeSignature)
    }

    func testPositionsMoveRightThroughAMeasure() throws {
        let layout = ScoreLayout(score: try longScore(), width: 2000)
        let xs = stride(from: 0.0, to: 4.0, by: 0.5).compactMap { layout.position(atQuarter: $0)?.x }
        XCTAssertEqual(xs.count, 8)
        XCTAssertEqual(xs, xs.sorted())
        XCTAssertEqual(Set(xs).count, 8)
        // Between onsets the position holds at the previous one (wait mode).
        XCTAssertEqual(layout.position(atQuarter: 0.25)?.x, layout.position(atQuarter: 0)?.x)
        XCTAssertNil(layout.position(atQuarter: 1000))
    }

    func testFindsTheNoteUnderAPoint() throws {
        let score = try longScore()
        let layout = ScoreLayout(score: score, width: 2000)
        let s = layout.metrics.spacing
        let measure = layout.systems[0].measures[0]
        // The first note is middle C, an eighth, on the treble staff's ledger line.
        let event = score.measures[0].events(onStaff: 0).sorted { $0.start < $1.start }[0]
        let x = try XCTUnwrap(measure.columns[event.start])
        let y = layout.y(ofStep: -2, staff: 0, system: 0)
        XCTAssertEqual(layout.note(atX: x, y: y), ScoreLayout.NoteHit(midi: 60, quarters: 0.5))
        XCTAssertEqual(layout.note(atX: x + 0.5 * s, y: y + 0.3 * s)?.midi, 60) // a little off the head
        XCTAssertNil(layout.note(atX: x, y: y - 3 * s))                         // empty staff above it
        XCTAssertNil(layout.note(atX: -100, y: y))
        // The bass staff's long G2.
        let bass = try XCTUnwrap(score.measures[0].events(onStaff: 1).first { !$0.isRest })
        let bx = try XCTUnwrap(measure.columns[bass.start])
        let by = layout.y(ofStep: Clef.bass.staffStep(of: bass.notes[0].spelled), staff: 1, system: 0)
        XCTAssertEqual(layout.note(atX: bx, y: by)?.midi, 43)
    }

        func testStaffStepsToY() throws {
        let layout = ScoreLayout(score: try longScore(), width: 800)
        let s = layout.metrics.spacing
        let top = layout.systems[0].staffTops[0]
        XCTAssertEqual(layout.y(ofStep: 8, staff: 0, system: 0), top, accuracy: 1e-9)          // top line
        XCTAssertEqual(layout.y(ofStep: 0, staff: 0, system: 0), top + 4 * s, accuracy: 1e-9)  // bottom line
        XCTAssertEqual(layout.y(ofStep: -2, staff: 0, system: 0), top + 5 * s, accuracy: 1e-9) // middle C ledger line
        XCTAssertEqual(Clef.treble.staffStep(of: KeySignature.cMajor.spell(60)), -2)
        XCTAssertEqual(Clef.bass.staffStep(of: KeySignature.cMajor.spell(60)), 10)
        XCTAssertEqual(Clef.treble.staffStep(of: KeySignature.cMajor.spell(77)), 8)            // F5 top line
    }

    func testStemDirection() {
        let key = KeySignature.cMajor
        func chord(_ pitches: [Int]) -> ScoreEvent {
            ScoreEvent(staff: 0, start: 0, duration: 4, type: .quarter, dots: 0, notes: pitches.map { ScoreNote(midi: $0, spelled: key.spell($0)) })
        }
        XCTAssertTrue(chord([64]).stemUp(clef: .treble))   // E4, bottom line
        XCTAssertFalse(chord([71]).stemUp(clef: .treble))  // B4, middle line
        XCTAssertFalse(chord([79]).stemUp(clef: .treble))  // G5
        XCTAssertTrue(chord([60, 64, 67]).stemUp(clef: .treble))
    }
}

final class StaffDetectionTests: XCTestCase {
    /// A white image with staves drawn in: five lines each, plus noteheads, a stem and a text row.
    private func page(width: Int = 400, height: Int = 300, staffTops: [Int], spacing: Int = 10, thickness: Int = 2) -> GrayImage {
        var pixels = [UInt8](repeating: 255, count: width * height)
        func dark(_ x: Int, _ y: Int) { if x >= 0, y >= 0, x < width, y < height { pixels[y * width + x] = 20 } }
        for top in staffTops {
            for line in 0..<5 {
                for t in 0..<thickness { for x in 10..<(width - 10) { dark(x, top + line * spacing + t) } }
            }
            // Noteheads and a stem crossing the lines.
            for cx in stride(from: 60, to: width - 40, by: 70) {
                for dy in -4...4 { for dx in -6...6 where dx * dx * 16 + dy * dy * 36 <= 600 { dark(cx + dx, top + 2 * spacing + dy) } }
                for y in (top - 25)...(top + 2 * spacing) { dark(cx + 6, y) }
            }
        }
        // A row of "text": dark in short bursts, never across the measure.
        for x in stride(from: 20, to: width - 20, by: 9) { for dx in 0..<4 { for y in 280..<288 { dark(x + dx, y) } } }
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    func testFindsOneStaff() throws {
        let staves = StaffLineDetector.detect(in: page(staffTops: [100]), x0: 0, x1: 400, y0: 40, y1: 300)
        XCTAssertEqual(staves.count, 1)
        let staff = try XCTUnwrap(staves.first)
        XCTAssertEqual(staff.top, 100.5, accuracy: 0.01)   // centre of a two-pixel line
        XCTAssertEqual(staff.spacing, 10, accuracy: 0.01)
    }

    func testFindsAGrandStaff() {
        let staves = StaffLineDetector.detect(in: page(staffTops: [40, 160], thickness: 1), x0: 0, x1: 400, y0: 0, y1: 300)
        XCTAssertEqual(staves.map(\.top), [40, 160])
        XCTAssertEqual(staves.map(\.bottom), [80, 200])
    }

    func testNothingInBlankOrTextRegions() {
        let image = page(staffTops: [100])
        XCTAssertTrue(StaffLineDetector.detect(in: image, x0: 0, x1: 400, y0: 200, y1: 300).isEmpty)
        XCTAssertTrue(StaffLineDetector.detect(in: image, x0: 0, x1: 400, y0: 0, y1: 4).isEmpty)
    }

    func testPlacementSteps() {
        let p = StaffPlacement(bottomLineY: 100, spacing: 8)
        XCTAssertEqual(p.topLineY, 132)
        XCTAssertEqual(p.y(ofStep: 0), 100)
        XCTAssertEqual(p.y(ofStep: 8), 132)
        XCTAssertEqual(p.y(ofStep: -2), 92) // ledger line below
    }

    /// Optional check against a real book page. Render one with
    ///   pdftoppm -f 29 -l 29 -r 216 -gray Books/learning-the-code-book1.pdf page
    /// and set PIANO_PAGE_PGM to the .pgm path; skipped otherwise.
    func testRealBookPage() throws {
        guard let path = ProcessInfo.processInfo.environment["PIANO_PAGE_PGM"] else { throw XCTSkip("PIANO_PAGE_PGM not set") }
        let image = try XCTUnwrap(readPGM(URL(fileURLWithPath: path)))
        let annotations = try BookAnnotations.load(url: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Books/learning-the-code-book1.annotations.json"))
        let passage = annotations.passages[0]
        let scale = Double(image.width) / 612 // US Letter width in points
        for m in passage.measures {
            let staves = StaffLineDetector.detect(
                in: image,
                x0: Int((m.box.x + 0.1 * m.box.width) * scale), x1: Int((m.box.maxX - 0.1 * m.box.width) * scale),
                y0: Int((792 - m.box.maxY) * scale), y1: Int((792 - m.box.y) * scale))
            XCTAssertEqual(staves.count, 1, "measure \(m.number)")
            if let staff = staves.first {
                // The book's staff lines are about 15 pt apart, and the staff sits inside the measure box.
                XCTAssertEqual(staff.spacing / scale, 15, accuracy: 2, "measure \(m.number)")
                let bottomLineY = 792 - staff.bottom / scale
                XCTAssertGreaterThan(bottomLineY, m.box.y, "measure \(m.number)")
                XCTAssertLessThan(bottomLineY + 4 * staff.spacing / scale, m.box.maxY, "measure \(m.number)")
            }
        }
    }

    private func readPGM(_ url: URL) -> GrayImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let bytes = [UInt8](data)
        var fields: [String] = []
        var i = 0
        while fields.count < 4, i < bytes.count {
            while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x0A || bytes[i] == 0x0D || bytes[i] == 0x09 { i += 1 }
            var token = ""
            while i < bytes.count, !(bytes[i] == 0x20 || bytes[i] == 0x0A || bytes[i] == 0x0D || bytes[i] == 0x09) {
                token.append(Character(UnicodeScalar(bytes[i])))
                i += 1
            }
            fields.append(token)
        }
        i += 1
        guard fields.first == "P5", let w = Int(fields[1]), let h = Int(fields[2]), bytes.count - i >= w * h else { return nil }
        return GrayImage(width: w, height: h, pixels: Array(bytes[i..<(i + w * h)]))
    }
}

final class AnnotationStaffTests: XCTestCase {
    func testOptionalStaffAndClefDecode() throws {
        let json = """
        {"id":"p","title":"t","page":1,"reference":"r.mid","clef":"bass",
         "box":{"x":0,"y":0,"width":10,"height":10},
         "measures":[{"number":1,"quarters":4,"box":{"x":0,"y":0,"width":10,"height":10},"beatX":[0,10],
                      "staff":{"bottomLineY":20,"spacing":7}},
                     {"number":2,"quarters":4,"box":{"x":0,"y":0,"width":10,"height":10},"beatX":[0,10]}]}
        """
        let p = try JSONDecoder().decode(PassageAnnotation.self, from: Data(json.utf8))
        XCTAssertEqual(p.clef, .bass)
        XCTAssertEqual(p.measures[0].staff, StaffPlacement(bottomLineY: 20, spacing: 7))
        XCTAssertNil(p.measures[1].staff)
    }
}

final class ScoreRendererTests: XCTestCase {
    private func score() throws -> Score {
        let notes = [note(67, 0, 1), note(69, 1, 0.5), note(71, 1.5, 0.5), note(72, 2, 2), note(48, 0, 4, track: 1)]
        return Transcriber().transcribe(try sequence(notes))
    }

    func testGlyphOutlinesParse() {
        for glyph in Glyph.allCases {
            let elements = glyph.elements
            XCTAssertFalse(elements.isEmpty, "\(glyph)")
            if case .move = elements.first {} else { XCTFail("\(glyph) should start with a move") }
        }
        // A black notehead is about 1.18 spaces wide and one space tall.
        XCTAssertEqual(Glyph.noteheadBlack.width, 1.18, accuracy: 0.01)
        XCTAssertEqual(SVGPathParser.parse("M0 0L1-1Z"), [.move(DrawPoint(0, 0)), .line(DrawPoint(1, -1)), .close])
    }

    func testScoreDrawingHasTheMusic() throws {
        let renderer = ScoreRenderer(layout: ScoreLayout(score: try score(), width: 800))
        let drawing = renderer.renderScore()
        var glyphs: [Glyph] = []
        for case let .glyph(g, _, _, _) in drawing.items { glyphs.append(g) }
        XCTAssertTrue(glyphs.contains(.gClef))
        XCTAssertTrue(glyphs.contains(.fClef))
        XCTAssertEqual(glyphs.filter { $0 == .noteheadBlack }.count, 3) // G4 quarter, A4 and B4 eighths
        XCTAssertEqual(glyphs.filter { $0 == .noteheadHalf }.count, 1)  // C5
        XCTAssertEqual(glyphs.filter { $0 == .noteheadWhole }.count, 1) // C3 in the bass
        // The two eighths share a beam rather than having flags.
        XCTAssertFalse(glyphs.contains(.flag8thUp) || glyphs.contains(.flag8thDown))
        XCTAssertTrue(drawing.items.contains { if case .shape = $0 { return true } else { return false } })
    }

    func testCleanTintsCanBeLeftOut() throws {
        let score = try score()
        let renderer = ScoreRenderer(layout: ScoreLayout(score: score, width: 800))
        let bars = score.measures.count
        let wrong = try XCTUnwrap(score.measures.first?.number)
        func tints(_ drawing: Drawing) -> (clean: Int, mistake: Int) {
            var clean = 0, mistake = 0
            for case let .rect(_, _, _, _, _, color) in drawing.items {
                if color == .cleanTint { clean += 1 }
                if color == .mistakeTint { mistake += 1 }
            }
            return (clean, mistake)
        }
        let all = tints(renderer.renderScore(mistakeMeasures: [wrong]))
        XCTAssertEqual(all.clean, bars - 1)
        XCTAssertEqual(all.mistake, 1)
        // Without clean tints, only the bar with a mistake is tinted.
        let redOnly = tints(renderer.renderScore(mistakeMeasures: [wrong], cleanTints: false))
        XCTAssertEqual(redOnly.clean, 0)
        XCTAssertEqual(redOnly.mistake, 1)
    }

    /// Centres of the see-through circles marking held wrong keys.
    private func playingCircles(_ items: [DrawItem]) -> [DrawPoint] {
        items.compactMap { item in
            if case let .rect(x, y, w, h, _, .playing) = item { return DrawPoint(x + w / 2, y + h / 2) }
            return nil
        }
    }

    func testLiveLayerMarksExpectedAndWrongNotes() throws {
        let layout = ScoreLayout(score: try score(), width: 800)
        let renderer = ScoreRenderer(layout: layout)
        XCTAssertTrue(renderer.renderLive(ScoreOverlay()).isEmpty)

        let live = renderer.renderLive(ScoreOverlay(cursorQuarter: 1, expected: [69], wrong: [70]))
        let expectedHeads = live.filter { if case .glyph(.noteheadBlack, _, _, .expected) = $0 { return true } else { return false } }
        XCTAssertEqual(expectedHeads.count, 1)
        // One plain circle in the playhead's column: no accidental, name or backing card.
        let circles = playingCircles(live)
        XCTAssertEqual(circles.count, 1)
        XCTAssertEqual(circles[0].x, try XCTUnwrap(layout.position(atQuarter: 1)).x, accuracy: 1e-6)
        XCTAssertFalse(live.contains { if case .text = $0 { return true } else { return false } })
        XCTAssertFalse(live.contains { if case .glyph(_, _, _, .wrong) = $0 { return true } else { return false } })
        // Nothing held, nothing marked.
        XCTAssertTrue(playingCircles(renderer.renderLive(ScoreOverlay(cursorQuarter: 1, expected: [69]))).isEmpty)
    }

    func testPlayheadBandAndHalos() throws {
        let layout = ScoreLayout(score: try score(), width: 800)
        let renderer = ScoreRenderer(layout: layout)
        let x = try XCTUnwrap(layout.position(atQuarter: 1)).x
        let band = renderer.renderPlayhead(ScoreOverlay(cursorQuarter: 1, expected: [69]))
        XCTAssertEqual(band.count, 1)
        guard case .rect(let bx, let by, let bw, let bh, _, .cursor) = band[0] else { return XCTFail("one band") }
        XCTAssertEqual(bx + bw / 2, x, accuracy: 1e-6)
        // Reaches above the top staff line and below the bottom one.
        let system = layout.systems[0]
        XCTAssertLessThan(by, system.staffTops[0])
        XCTAssertGreaterThan(by + bh, system.staffTops.last! + 4 * layout.metrics.spacing)
        // A halo behind the wanted note.
        let live = renderer.renderLive(ScoreOverlay(cursorQuarter: 1, expected: [69]))
        XCTAssertEqual(live.filter { if case .rect(_, _, _, _, _, .expectedHalo) = $0 { return true } else { return false } }.count, 1)
        // Listening: the audition colour, no halos.
        guard case .rect(_, _, _, _, _, .audition)? = renderer.renderPlayhead(ScoreOverlay(cursorQuarter: 1, auditioning: true)).first
        else { return XCTFail("audition band") }
        XCTAssertTrue(renderer.renderPlayhead(ScoreOverlay()).isEmpty)
    }

    func testWrongNotesBelowMiddleCGoOnTheBassStaff() throws {
        let layout = ScoreLayout(score: try score(), width: 800)
        let live = ScoreRenderer(layout: layout).renderLive(ScoreOverlay(cursorQuarter: 0, wrong: [50]))
        let centre = try XCTUnwrap(playingCircles(live).first)
        // D3 is the middle line of the bass staff.
        XCTAssertEqual(centre.y, layout.systems[0].staffTops[1] + 2 * layout.metrics.spacing, accuracy: 1e-6)
    }

    func testLedgerLinesForHeldKeysOffTheStaff() {
        // C4 on a treble staff: one ledger line below, plus the circle.
        let items = PlayedNoteMarks.items(pitches: [60], key: .cMajor, clef: .treble, x: 100, spacing: 10,
                                          yOfStep: { 200 - Double($0) * 5 })
        let ledgers = items.filter { if case .line(_, _, _, .playing) = $0 { return true } else { return false } }
        XCTAssertEqual(ledgers.count, 1)
        XCTAssertEqual(playingCircles(items).map(\.y), [210])
        // A second apart: two circles, side by side.
        let pair = playingCircles(PlayedNoteMarks.items(pitches: [64, 65], key: .cMajor, clef: .treble, x: 100, spacing: 10,
                                                         yOfStep: { 200 - Double($0) * 5 }))
        XCTAssertEqual(pair.count, 2)
        XCTAssertNotEqual(pair[0].x, pair[1].x)
    }

    func testPlayedNotesTurnGreenIncludingTiedContinuations() throws {
        // C5 half note at beat 3 of a 4/4 bar, held into the next bar: written tied.
        let notes = [note(67, 0, 1), note(69, 1, 1), note(72, 2, 4)]
        let layout = ScoreLayout(score: Transcriber().transcribe(try sequence(notes)), width: 800)
        let renderer = ScoreRenderer(layout: layout)
        XCTAssertTrue(renderer.renderPlayed([]).isEmpty)

        func greenHeads(_ items: [DrawItem]) -> Int {
            items.filter { if case .glyph(let g, _, _, .played) = $0 { return g == .noteheadBlack || g == .noteheadHalf } else { return false } }.count
        }
        XCTAssertEqual(greenHeads(renderer.renderPlayed([PlayedNote(quarter: 0, pitch: 67)])), 1)
        // Slightly off-grid onsets (as in a played-in file) still find their note.
        XCTAssertEqual(greenHeads(renderer.renderPlayed([PlayedNote(quarter: 0.98, pitch: 69)])), 1)
        // The tied C5: both written halves go green.
        XCTAssertEqual(greenHeads(renderer.renderPlayed([PlayedNote(quarter: 2, pitch: 72)])), 2)
        // A pitch that isn't there marks nothing.
        XCTAssertEqual(greenHeads(renderer.renderPlayed([PlayedNote(quarter: 0, pitch: 61)])), 0)
    }

    func testPlayedNotesGetGreenStemsFlagsAndBeams() throws {
        // A quarter, a lone eighth (flag) after a dotted quarter, then two beamed eighths.
        let notes = [note(67, 0, 1), note(69, 1, 1.5), note(71, 2.5, 0.5), note(72, 3, 0.5), note(74, 3.5, 0.5)]
        let renderer = ScoreRenderer(layout: ScoreLayout(score: Transcriber().transcribe(try sequence(notes)), width: 800))
        func count(_ items: [DrawItem]) -> (stems: Int, flags: Int, beams: Int) {
            var r = (0, 0, 0)
            for item in items {
                switch item {
                case .line(_, _, _, .played): r.0 += 1
                case .glyph(.flag8thUp, _, _, .played), .glyph(.flag8thDown, _, _, .played): r.1 += 1
                case .shape(_, .played): r.2 += 1
                default: break
                }
            }
            return r
        }
        let all = notes.map { PlayedNote(quarter: $0.onset * 2, pitch: $0.pitch) } // 120 bpm: seconds × 2 = quarters
        let everything = count(renderer.renderPlayed(all))
        XCTAssertEqual(everything.stems, 5)
        XCTAssertEqual(everything.flags, 1)
        XCTAssertEqual(everything.beams, 1)
        // Half the beamed pair played: its stem goes green, the beam waits.
        let half = count(renderer.renderPlayed(Array(all.prefix(4))))
        XCTAssertEqual(half.stems, 4)
        XCTAssertEqual(half.beams, 0)
        // A chord with one note still to play keeps a black stem.
        let chord = ScoreRenderer(layout: ScoreLayout(score: Transcriber().transcribe(try sequence(
            [note(60, 0, 1), note(64, 0, 1)])), width: 600))
        XCTAssertEqual(count(chord.renderPlayed([PlayedNote(quarter: 0, pitch: 60)])).stems, 0)
        XCTAssertEqual(count(chord.renderPlayed([PlayedNote(quarter: 0, pitch: 60), PlayedNote(quarter: 0, pitch: 64)])).stems, 1)
    }

    func testChordPartlyPlayedIsPartlyGreen() throws {
        let renderer = ScoreRenderer(layout: ScoreLayout(score: Transcriber().transcribe(try sequence(
            [note(60, 0, 1), note(64, 0, 1), note(67, 0, 1)])), width: 600))
        let items = renderer.renderPlayed([PlayedNote(quarter: 0, pitch: 60), PlayedNote(quarter: 0, pitch: 64)])
        XCTAssertEqual(items.filter { if case .glyph(.noteheadBlack, _, _, .played) = $0 { return true } else { return false } }.count, 2)
    }

    func testSVGIsWellFormed() throws {
        let svg = ScoreRenderer(layout: ScoreLayout(score: try score(), width: 600))
            .render(ScoreOverlay(cursorQuarter: 1, expected: [69], wrong: [70], mistakeMeasures: [1])).svg()
        let parser = XMLParser(data: Data(svg.utf8))
        XCTAssertTrue(parser.parse())
        XCTAssertTrue(svg.contains("check m1"))
    }
}

final class FingeringTests: XCTestCase {
    private func fingerTexts(_ items: [DrawItem]) -> [(String, DrawPoint)] {
        items.compactMap { item in
            if case .text(let s, let at, _, _, _, _) = item, Int(s) != nil { return (s, at) }
            return nil
        }
    }

    /// C D E D C as quarters: one number per note, left to right, above the staff.
    func testOneNumberPerNoteInOrder() throws {
        let seq = try MIDIFile.parse(MIDIFile.write(notes: [60, 62, 64, 62, 60].enumerated().map {
            NoteEvent(pitch: $0.element, onset: Double($0.offset) * 0.5, offset: Double($0.offset) * 0.5 + 0.45, velocity: 80)
        }))
        let score = Transcriber().transcribe(seq)
        let layout = ScoreLayout(score: score, width: 800)
        let renderer = ScoreRenderer(layout: layout)
        let marks = fingerTexts(renderer.renderFingering([1, 2, 3, 2, 1]))
        XCTAssertEqual(marks.map(\.0), ["1", "2", "3", "2", "1"])
        let xs = marks.map(\.1.x)
        XCTAssertEqual(xs, xs.sorted(), "left to right")
        let staffTop = layout.y(ofStep: 8, staff: 0, system: 0)
        XCTAssertTrue(marks.allSatisfy { $0.1.y < staffTop }, "above the staff")
    }

    func testFewerOrMoreNumbersThanNotes() throws {
        let seq = try MIDIFile.parse(MIDIFile.write(notes: [60, 62, 64].enumerated().map {
            NoteEvent(pitch: $0.element, onset: Double($0.offset) * 0.5, offset: Double($0.offset) * 0.5 + 0.45, velocity: 80)
        }))
        let renderer = ScoreRenderer(layout: ScoreLayout(score: Transcriber().transcribe(seq), width: 800))
        XCTAssertEqual(fingerTexts(renderer.renderFingering([1])).map(\.0), ["1"])
        XCTAssertEqual(fingerTexts(renderer.renderFingering([1, 2, 3, 4, 5])).map(\.0), ["1", "2", "3"])
        XCTAssertTrue(renderer.renderFingering([]).isEmpty)
        // renderScore includes them only when asked.
        XCTAssertEqual(fingerTexts(renderer.renderScore().items).count, 0)
        XCTAssertEqual(fingerTexts(renderer.renderScore(fingering: [1, 2, 3]).items).map(\.0), ["1", "2", "3"])
    }

    /// Both hands: right-hand numbers over the treble staff, left-hand numbers under the bass.
    func testLeftHandNumbersGoUnderTheBassStaff() throws {
        let right = [64, 65, 67].enumerated().map {
            NoteEvent(pitch: $0.element, onset: Double($0.offset) * 0.5, offset: Double($0.offset) * 0.5 + 0.45, velocity: 80)
        }
        let left = [48, 50, 52].enumerated().map {
            NoteEvent(pitch: $0.element, onset: Double($0.offset) * 0.5, offset: Double($0.offset) * 0.5 + 0.45, velocity: 80)
        }
        let score = Transcriber().transcribe(try MIDIFile.parse(MIDIFile.write(notes: right + left)))
        XCTAssertEqual(score.staves, [.treble, .bass])
        let layout = ScoreLayout(score: score, width: 800)
        let renderer = ScoreRenderer(layout: layout)
        let marks = fingerTexts(renderer.renderLeftFingering([5, 4, 3]))
        XCTAssertEqual(marks.map(\.0), ["5", "4", "3"])
        let xs = marks.map(\.1.x)
        XCTAssertEqual(xs, xs.sorted(), "left to right")
        let bassBottom = layout.y(ofStep: 0, staff: 1, system: 0)
        XCTAssertTrue(marks.allSatisfy { $0.1.y > bassBottom + 1.4 * layout.metrics.spacing }, "under the bass staff")
        let both = fingerTexts(renderer.renderScore(fingering: [3, 4, 5], leftFingering: [5, 4, 3]).items)
        XCTAssertEqual(both.map(\.0), ["3", "4", "5", "5", "4", "3"])
        let trebleTop = layout.y(ofStep: 8, staff: 0, system: 0)
        XCTAssertTrue(both.prefix(3).allSatisfy { $0.1.y < trebleTop }, "right hand still over the treble staff")
    }

    /// A left-hand-only passage on one bass staff: numbers under it.
    func testLeftHandAloneOnOneStaff() throws {
        let seq = try MIDIFile.parse(MIDIFile.write(notes: [48, 50, 52].enumerated().map {
            NoteEvent(pitch: $0.element, onset: Double($0.offset) * 0.5, offset: Double($0.offset) * 0.5 + 0.45, velocity: 80)
        }))
        let score = Transcriber().transcribe(seq)
        XCTAssertEqual(score.staves, [.bass])
        let layout = ScoreLayout(score: score, width: 800)
        let marks = fingerTexts(ScoreRenderer(layout: layout).renderLeftFingering([5, 4, 3]))
        XCTAssertEqual(marks.map(\.0), ["5", "4", "3"])
        XCTAssertTrue(marks.allSatisfy { $0.1.y > layout.y(ofStep: 0, staff: 0, system: 0) }, "under the staff")
    }
}
