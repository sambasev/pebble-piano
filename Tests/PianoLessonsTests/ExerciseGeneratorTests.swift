import XCTest
import PianoGraderCore
@testable import PianoLessons

final class ExerciseGeneratorTests: XCTestCase {
    private func make(_ kind: ExerciseGenerator.Kind, _ key: String, octaves: Int = 1, hand: Hand = .right) throws -> ExerciseGenerator.Exercise {
        try ExerciseGenerator.generate(.init(kind: kind, key: try XCTUnwrap(ExerciseGenerator.Key(key)), octaves: octaves, hand: hand))
    }

    private func names(_ e: ExerciseGenerator.Exercise, hand: Hand = .right) -> [String] {
        e.fingering.filter { $0.hand == hand }.map { PitchName.of($0.pitch) }
    }

    private func fingers(_ e: ExerciseGenerator.Exercise, hand: Hand = .right) -> [Int] {
        e.fingering.filter { $0.hand == hand }.map(\.finger)
    }

    func testKeysParseSpellingsAndQualities() throws {
        let g = try XCTUnwrap(ExerciseGenerator.Key("G"))
        XCTAssertEqual(g.tonic, 7); XCTAssertFalse(g.isMinor)
        XCTAssertEqual(ExerciseGenerator.Key("Bb")?.tonic, 10)
        XCTAssertEqual(ExerciseGenerator.Key("B♭")?.name, "Bb")
        XCTAssertEqual(ExerciseGenerator.Key("f# minor")?.tonic, 6)
        XCTAssertEqual(ExerciseGenerator.Key("Am")?.isMinor, true)
        XCTAssertEqual(ExerciseGenerator.Key("C major")?.isMinor, false)
        XCTAssertNil(ExerciseGenerator.Key("H"))
        XCTAssertNil(ExerciseGenerator.Key("Cbb"))
        XCTAssertNil(ExerciseGenerator.Key("C lydian"))
        XCTAssertNil(ExerciseGenerator.Key(""))
        XCTAssertEqual(ExerciseGenerator.Key("F")?.signature(minor: false).fifths, -1)
        XCTAssertEqual(ExerciseGenerator.Key("A")?.signature(minor: true).fifths, 0)
        XCTAssertEqual(ExerciseGenerator.Key("C")?.signature(minor: true).fifths, -3)
        XCTAssertEqual(ExerciseGenerator.Key("F#")?.signature(minor: false).fifths, 6)
        XCTAssertEqual(ExerciseGenerator.Key("D#")?.signature(minor: true).fifths, 6)
    }

    func testCMajorScaleRightHandUsesStandardFingering() throws {
        let e = try make(.majorScale, "C")
        XCTAssertEqual(names(e), ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5", "B4", "A4", "G4", "F4", "E4", "D4", "C4"])
        XCTAssertEqual(Array(fingers(e).prefix(8)), [1, 2, 3, 1, 2, 3, 4, 5])
        XCTAssertEqual(fingers(e), [1, 2, 3, 1, 2, 3, 4, 5, 4, 3, 2, 1, 3, 2, 1])
        XCTAssertEqual(e.title, "C major scale, 1 octave, right hand")
        XCTAssertEqual(e.sequence.keySignature, .cMajor)
    }

    func testFMajorRightHandPutsFourOnBFlat() throws {
        let e = try make(.majorScale, "F")
        let up = e.fingering.prefix(8)
        XCTAssertEqual(up.map(\.pitch), [65, 67, 69, 70, 72, 74, 76, 77])
        XCTAssertEqual(up.first { $0.pitch == 70 }?.finger, 4)
        XCTAssertEqual(up.map(\.finger), [1, 2, 3, 4, 1, 2, 3, 4])
    }

    func testTwoOctaveScalesCrossTheThumbAndEndOnTheRightFinger() throws {
        let rh = try make(.majorScale, "C", octaves: 2)
        XCTAssertEqual(Array(fingers(rh).prefix(15)), [1, 2, 3, 1, 2, 3, 4, 1, 2, 3, 1, 2, 3, 4, 5])
        let lh = try make(.majorScale, "C", octaves: 2, hand: .left)
        XCTAssertEqual(Array(fingers(lh, hand: .left).prefix(15)), [5, 4, 3, 2, 1, 3, 2, 1, 4, 3, 2, 1, 3, 2, 1])
        XCTAssertEqual(lh.fingering.first?.pitch, 48)
        let bFlat = try make(.majorScale, "Bb", octaves: 2)
        XCTAssertEqual(Array(fingers(bFlat).prefix(15)), [4, 1, 2, 3, 1, 2, 3, 4, 1, 2, 3, 1, 2, 3, 4])
    }

    func testMinorScalesUseTheirIntervals() throws {
        XCTAssertEqual(names(try make(.naturalMinorScale, "A")).prefix(8), ["A4", "B4", "C5", "D5", "E5", "F5", "G5", "A5"])
        XCTAssertEqual(names(try make(.harmonicMinorScale, "A")).prefix(8), ["A4", "B4", "C5", "D5", "E5", "F5", "G#5", "A5"])
        let minor = try make(.harmonicMinorScale, "A")
        XCTAssertEqual(minor.sequence.keySignature, KeySignature(fifths: 0, isMinor: true))
        XCTAssertEqual(minor.title, "A harmonic minor scale, 1 octave, right hand")
    }

    func testHandsTogetherPutsTheLeftHandAnOctaveBelowOnItsOwnTrack() throws {
        let e = try make(.majorScale, "G", hand: .both)
        let right = e.sequence.notes.filter { $0.track == 0 }, left = e.sequence.notes.filter { $0.track == 1 }
        XCTAssertEqual(right.count, 15); XCTAssertEqual(left.count, 15)
        XCTAssertEqual(zip(right, left).map { $0.pitch - $1.pitch }, Array(repeating: 12, count: 15))
        XCTAssertTrue(e.sequence.hasTwoHands)
        XCTAssertEqual(e.sequence.hand(.left).notes.map(\.pitch), left.map(\.pitch))
        XCTAssertEqual(Array(fingers(e, hand: .left).prefix(8)), [5, 4, 3, 2, 1, 3, 2, 1])
    }

    func testArpeggiosAndBrokenChords() throws {
        let arp = try make(.arpeggio, "C", octaves: 2)
        XCTAssertEqual(names(arp).prefix(7), ["C4", "E4", "G4", "C5", "E5", "G5", "C6"])
        XCTAssertEqual(Array(fingers(arp).prefix(7)), [1, 2, 3, 1, 2, 3, 5])
        let leftArp = try make(.arpeggio, "C", octaves: 2, hand: .left)
        XCTAssertEqual(Array(fingers(leftArp, hand: .left).prefix(7)), [5, 4, 2, 1, 4, 2, 1])
        XCTAssertEqual(Array(fingers(try make(.arpeggio, "Eb")).prefix(4)), [2, 1, 2, 4])
        XCTAssertEqual(names(try make(.arpeggio, "A minor")).prefix(4), ["A4", "C5", "E5", "A5"])

        let broken = try make(.brokenChord, "C")
        XCTAssertEqual(names(broken), ["C4", "E4", "G4", "E4", "E4", "G4", "C5", "G4", "G4", "C5", "E5", "C5", "C5"])
        XCTAssertEqual(fingers(broken), [1, 3, 5, 3, 1, 2, 5, 2, 1, 3, 5, 3, 1])
    }

    func testFiveFingerPattern() throws {
        let e = try make(.fiveFinger, "D minor", octaves: 2)
        XCTAssertEqual(names(e), ["D4", "E4", "F4", "G4", "A4", "G4", "F4", "E4", "D4"])
        XCTAssertEqual(fingers(e), [1, 2, 3, 4, 5, 4, 3, 2, 1])
        XCTAssertEqual(fingers(try make(.fiveFinger, "C", hand: .left), hand: .left), [5, 4, 3, 2, 1, 2, 3, 4, 5])
        XCTAssertEqual(e.title, "D minor five-finger pattern, right hand")
    }

    func testEveryKindKeyAndHandStaysOnTheKeyboardAndFillsWholeBars() throws {
        let keys = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        var generated = 0
        for kind in ExerciseGenerator.Kind.allCases {
            for key in keys + keys.map({ $0 + " minor" }) {
                for octaves in 1...2 {
                    for hand in [Hand.right, .left, .both] {
                        guard let e = try? make(kind, key, octaves: octaves, hand: hand) else {
                            // Only the widest pattern, two octaves of broken chords with both hands, may not fit.
                            XCTAssertTrue(kind == .brokenChord && octaves == 2 && hand == .both, "\(kind) \(key) \(octaves) \(hand)")
                            continue
                        }
                        generated += 1
                        XCTAssertTrue(e.sequence.notes.allSatisfy { ExerciseGenerator.range.contains($0.pitch) }, e.title)
                        XCTAssertEqual(e.fingering.count, e.sequence.notes.count)
                        XCTAssertTrue(e.fingering.allSatisfy { (1...5).contains($0.finger) })
                        XCTAssertEqual(e.sequence.measureCount, Int(ceil(Double(e.fingering.filter { $0.hand != .left || hand == .left }.count) / 4)), e.title)
                    }
                }
            }
        }
        XCTAssertGreaterThan(generated, 400)
    }

    func testSameRequestGivesTheSameExercise() throws {
        let a = try make(.harmonicMinorScale, "G#", octaves: 2, hand: .both)
        let b = try make(.harmonicMinorScale, "G#", octaves: 2, hand: .both)
        XCTAssertEqual(a.sequence.notes, b.sequence.notes)
        XCTAssertEqual(a.fingering, b.fingering)
    }

    func testBadOctavesAreRefused() throws {
        XCTAssertThrowsError(try make(.majorScale, "C", octaves: 3)) { XCTAssertEqual($0 as? ExerciseGenerator.Failure, .octaves) }
        XCTAssertThrowsError(try make(.majorScale, "C", octaves: 0))
    }
}
