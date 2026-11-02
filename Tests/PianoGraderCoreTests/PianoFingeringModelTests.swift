import XCTest
@testable import PianoGraderCore

final class PianoFingeringModelTests: XCTestCase {

    func testKeyboardGeometry() {
        XCTAssertFalse(KeyboardGeometry.isBlackKey(60)) // C4
        XCTAssertTrue(KeyboardGeometry.isBlackKey(61))  // C#4
        XCTAssertFalse(KeyboardGeometry.isBlackKey(62)) // D4
        XCTAssertTrue(KeyboardGeometry.isBlackKey(63))  // D#4
        XCTAssertFalse(KeyboardGeometry.isBlackKey(64)) // E4
        XCTAssertFalse(KeyboardGeometry.isBlackKey(65)) // F4
        XCTAssertTrue(KeyboardGeometry.isBlackKey(66))  // F#4

        // Distance in white keys
        let distCE = KeyboardGeometry.distance(from: 60, to: 64)
        XCTAssertEqual(distCE, 2.0, accuracy: 0.01)

        let distCG = KeyboardGeometry.distance(from: 60, to: 67)
        XCTAssertEqual(distCG, 4.0, accuracy: 0.01)

        let distOctave = KeyboardGeometry.distance(from: 60, to: 72)
        XCTAssertEqual(distOctave, 7.0, accuracy: 0.01)
    }

    func testRightHandFiveFingerAscending() {
        // C4, D4, E4, F4, G4 in RH
        let pitches = [60, 62, 64, 65, 67]
        let fingers = NakamuraFingeringHMM.solveMonophonic(pitches: pitches, hand: .right)
        XCTAssertEqual(fingers, [1, 2, 3, 4, 5])
    }

    func testRightHandFiveFingerDescending() {
        // G4, F4, E4, D4, C4 in RH
        let pitches = [67, 65, 64, 62, 60]
        let fingers = NakamuraFingeringHMM.solveMonophonic(pitches: pitches, hand: .right)
        XCTAssertEqual(fingers, [5, 4, 3, 2, 1])
    }

    func testLeftHandFiveFingerAscending() {
        // C3, D3, E3, F3, G3 in LH
        let pitches = [48, 50, 52, 53, 55]
        let fingers = NakamuraFingeringHMM.solveMonophonic(pitches: pitches, hand: .left)
        XCTAssertEqual(fingers, [5, 4, 3, 2, 1])
    }

    func testScaleThumbUnderPivot() {
        // C major octave scale: C4, D4, E4, F4, G4, A4, B4, C5
        let scale = [60, 62, 64, 65, 67, 69, 71, 72]
        let fingers = NakamuraFingeringHMM.solveMonophonic(pitches: scale, hand: .right)
        // Standard fingering passes thumb under at note 4 (F4)
        XCTAssertEqual(fingers, [1, 2, 3, 1, 2, 3, 4, 5])
    }

    func testScaleCrossOverPivot() {
        // C major descending: C5, B4, A4, G4, F4, E4, D4, C4
        let scale = [72, 71, 69, 67, 65, 64, 62, 60]
        let fingers = NakamuraFingeringHMM.solveMonophonic(pitches: scale, hand: .right)
        // Standard fingering crosses finger 3 over thumb at note 6 (E4)
        XCTAssertEqual(fingers, [5, 4, 3, 2, 1, 3, 2, 1])
    }

    func testChordsVoicing() {
        // C major triad C4-E4-G4 in RH
        let rhTriad = NakamuraFingeringHMM.solveChord(pitches: [60, 64, 67], hand: .right)
        XCTAssertEqual(rhTriad, [1, 3, 5])

        // C major triad C3-E3-G3 in LH
        let lhTriad = NakamuraFingeringHMM.solveChord(pitches: [48, 52, 55], hand: .left)
        XCTAssertEqual(lhTriad, [5, 3, 1])

        // Octave C4-C5
        let octave = NakamuraFingeringHMM.solveChord(pitches: [60, 72], hand: .right)
        XCTAssertEqual(octave, [1, 5])
    }

    func testAnchorConstraint() {
        // C4, D4, E4 starting with finger 2 as an explicit anchor
        let pitches = [60, 62, 64]
        let fingers = NakamuraFingeringHMM.solveMonophonic(pitches: pitches, hand: .right, anchors: [0: 2])
        XCTAssertEqual(fingers.first, 2)
        XCTAssertEqual(fingers, [2, 3, 4])
    }

    func testAnalyzeMIDISequence() throws {
        // Create a simple sequence: C4, D4, E4, F4, G4 quarter notes
        let notes = [
            NoteEvent(pitch: 60, onset: 0.0, offset: 0.5, onsetBeats: 0.0, offsetBeats: 1.0),
            NoteEvent(pitch: 62, onset: 0.5, offset: 1.0, onsetBeats: 1.0, offsetBeats: 2.0),
            NoteEvent(pitch: 64, onset: 1.0, offset: 1.5, onsetBeats: 2.0, offsetBeats: 3.0),
            NoteEvent(pitch: 65, onset: 1.5, offset: 2.0, onsetBeats: 3.0, offsetBeats: 4.0),
            NoteEvent(pitch: 67, onset: 2.0, offset: 2.5, onsetBeats: 4.0, offsetBeats: 5.0)
        ]
        let seq = MIDISequence(notes: notes, ticksPerQuarter: 480, initialTempoBPM: 120, timeSignature: .common)
        let fingered = PianoFingeringModel.analyze(sequence: seq)
        XCTAssertEqual(fingered.count, 5)
        XCTAssertEqual(fingered.map(\.finger), [1, 2, 3, 4, 5])
        XCTAssertEqual(fingered.map(\.hand), [.right, .right, .right, .right, .right])
    }

    func testOdeToJoyFingering() throws {
        let odeURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Examples/ode-to-joy-c.mid")
        let seq = try MIDIFile.read(url: odeURL)
        let score = Transcriber().transcribe(seq, title: "Ode to Joy")
        let fingered = PianoFingeringModel.analyze(score: score)

        var rendererEvents: [(measure: Int, pitch: Int)] = []
        for m in score.measures {
            for event in m.events(onStaff: 0).sorted(by: { $0.start < $1.start }) {
                if !event.isRest && !event.notes.allSatisfy(\.tieStop) {
                    rendererEvents.append((m.number, event.notes.first?.midi ?? 0))
                }
            }
        }
        XCTAssertEqual(rendererEvents.count, fingered.count, "Fingered notes must match non-tied score events 1-to-1")

        for i in 0..<rendererEvents.count {
            let re = rendererEvents[i]
            let fn = fingered[i]
            XCTAssertEqual(re.pitch, fn.pitch, "Event pitch at index \(i) must match")
            XCTAssertEqual(re.measure, fn.measureNumber, "Event measure at index \(i) must match")
        }

        // Measure 10: E E F G -> [3, 3, 4, 5] (never 2 3 3 4)
        let m10Fingers = fingered.filter { $0.measureNumber == 10 }.map(\.finger)
        XCTAssertEqual(m10Fingers, [3, 3, 4, 5], "Measure 10 should be 3 3 4 5")

        // Measure 11: G F E D -> [5, 4, 3, 2] (never 5 5 4 3)
        let m11Fingers = fingered.filter { $0.measureNumber == 11 }.map(\.finger)
        XCTAssertEqual(m11Fingers, [5, 4, 3, 2], "Measure 11 should be 5 4 3 2")

        // Measure 12: C C D E -> [1, 1, 2, 3] (never 2 1 1 2)
        let m12Fingers = fingered.filter { $0.measureNumber == 12 }.map(\.finger)
        XCTAssertEqual(m12Fingers, [1, 1, 2, 3], "Measure 12 should be 1 1 2 3")

        // Measure 14: D D E C -> [2, 2, 3, 1]
        let m14Fingers = fingered.filter { $0.measureNumber == 14 }.map(\.finger)
        XCTAssertEqual(m14Fingers, [2, 2, 3, 1], "Measure 14 (D D E C) should be finger 2 2 3 1")

        // Measure 15: D E F E C -> [2, 3, 4, 3, 1]
        let m15Fingers = fingered.filter { $0.measureNumber == 15 }.map(\.finger)
        XCTAssertEqual(m15Fingers, [2, 3, 4, 3, 1], "Measure 15 (D E F E C) should be finger 2 3 4 3 1")

        // Measure 16: D E F E D -> [2, 3, 4, 3, 2]
        let m16Fingers = fingered.filter { $0.measureNumber == 16 }.map(\.finger)
        XCTAssertEqual(m16Fingers, [2, 3, 4, 3, 2], "Measure 16 (D E F E D) should be finger 2 3 4 3 2")

        // Measure 18: E E F G -> [3, 3, 4, 5] (never 5 3 4 5 or 2 1 1 3)
        let m18Fingers = fingered.filter { $0.measureNumber == 18 }.map(\.finger)
        XCTAssertEqual(m18Fingers, [3, 3, 4, 5], "Measure 18 (E E F G) should be finger 3 3 4 5")
    }

    func testHotCrossBunsFingering() {
        // Hot Cross Buns: E4, D4, C4, E4, D4, C4, C4 C4 C4 C4, D4 D4 D4 D4, E4 D4 C4
        let pitches = [64, 62, 60, 64, 62, 60, 60, 60, 60, 60, 62, 62, 62, 62, 64, 62, 60]
        let fingers = NakamuraFingeringHMM.solveMonophonic(pitches: pitches, hand: .right)
        XCTAssertEqual(Array(fingers.prefix(3)), [3, 2, 1], "Initial three notes must be 3 2 1")
        XCTAssertEqual(fingers, [
            3, 2, 1,
            3, 2, 1,
            1, 1, 1, 1,
            2, 2, 2, 2,
            3, 2, 1
        ], "Entire Hot Cross Buns in RH C-position must use fingers 3, 2, 1")
    }

    func testMaryHadALittleLambFingering() {
        // Mary Had a Little Lamb: E4 D4 C4 D4 E4 E4 E4, D4 D4 D4, E4 G4 G4...
        let pitches = [64, 62, 60, 62, 64, 64, 64, 62, 62, 62, 64, 67, 67]
        let fingers = NakamuraFingeringHMM.solveMonophonic(pitches: pitches, hand: .right)
        XCTAssertEqual(Array(fingers.prefix(4)), [3, 2, 1, 2])
        XCTAssertEqual(fingers, [3, 2, 1, 2, 3, 3, 3, 2, 2, 2, 3, 5, 5])
    }
}
