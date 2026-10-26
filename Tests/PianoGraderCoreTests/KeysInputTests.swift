import XCTest
@testable import PianoGraderCore

/// The computer keyboard (musical typing or clicking the on-screen keys) gets its own extra
/// lateness in play-along, and grading never looks at how long its notes last.
final class KeysInputTests: XCTestCase {
    func testDefaults() {
        let p = Rubric.PlayAlong()
        XCTAssertEqual(p.keysExtraLateMs, 150)
        XCTAssertEqual(p.extraLateMs(for: .midi), 0)
        XCTAssertEqual(p.extraLateMs(for: .microphone), 120)
        XCTAssertEqual(p.extraLateMs(for: .computerKeyboard), 150)
        XCTAssertEqual(Rubric.PlayAlong.strict.keysExtraLateMs, 100, "strict is tighter for keys too")
        XCTAssertEqual(Rubric.PlayAlong.gentle.keysExtraLateMs, 150)
    }

    func testJudgeSettingsPerInput() {
        let p = Rubric.PlayAlong()
        XCTAssertEqual(p.judgeSettings(input: .midi).lateSeconds, 0.40, accuracy: 1e-9)
        XCTAssertEqual(p.judgeSettings(input: .microphone).lateSeconds, 0.52, accuracy: 1e-9)
        XCTAssertEqual(p.judgeSettings(input: .computerKeyboard).lateSeconds, 0.55, accuracy: 1e-9)
        XCTAssertEqual(p.judgeSettings(input: .computerKeyboard).earlySeconds, 0.25, accuracy: 1e-9,
                       "only lateness changes")
        XCTAssertEqual(p.judgeSettings(microphone: true).lateSeconds, 0.52, accuracy: 1e-9, "old API still works")
        XCTAssertEqual(p.judgeSettings(microphone: false).lateSeconds, 0.40, accuracy: 1e-9)
    }

    func testParsedFromTheRubric() throws {
        let rubric = try Rubric.parse("""
        ---
        play_along:
          keys_extra_late_ms: 90
        ---
        """)
        XCTAssertEqual(rubric.playAlong.keysExtraLateMs, 90)
        XCTAssertEqual(rubric.playAlong.micExtraLateMs, 120, "default kept")
        XCTAssertEqual(try Rubric.parse("level: beginner").playAlong.keysExtraLateMs, 150, "missing key → default")
    }

    func testTheBundledRubricFiles() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let beginner = try Rubric.load(url: root.appendingPathComponent("Rubrics/beginner.md"))
        XCTAssertEqual(beginner.playAlong.keysExtraLateMs, 150)
        let intermediate = try Rubric.load(url: root.appendingPathComponent("Rubrics/intermediate.md"))
        XCTAssertEqual(intermediate.playAlong.keysExtraLateMs, 100)
    }

    /// 120 bpm: 0.5 s per quarter. A note half a second late (one quarter) misses the MIDI
    /// window (0.40 s) but counts on the computer keyboard (0.55 s).
    func testHalfASecondLateCountsOnlyForKeys() {
        let clock = BeatClock(bpm: 120)
        let chords: [(quarter: Double, pitches: Set<Int>)] = [(quarter: 0, pitches: [60]), (quarter: 4, pitches: [62])]
        var lax = Rubric.PlayAlong()
        lax.maxMissFraction = 1
        lax.maxMissesPerBar = 4

        var midi = PlayAlongJudge(chords: chords, clock: clock, settings: lax.judgeSettings(input: .midi))
        midi.noteOn(60, atQuarter: 1.0)
        _ = midi.advance(toQuarter: 1.5)
        XCTAssertEqual(midi.states[0], .missed)

        var keys = PlayAlongJudge(chords: chords, clock: clock, settings: lax.judgeSettings(input: .computerKeyboard))
        keys.noteOn(60, atQuarter: 1.0)
        _ = keys.advance(toQuarter: 1.5)
        XCTAssertEqual(keys.states[0], .hit)
    }

    /// Typed notes all last the same time (terminals and key repeat give no real releases).
    /// Grading uses onsets only, so short or long notes grade exactly like the reference.
    func testNoteLengthsDontAffectTheGrade() {
        func sequence(duration: Double?) -> MIDISequence {
            let notes = [60, 62, 64, 65, 67, 65, 64, 62, 60].enumerated().map { i, pitch in
                NoteEvent(pitch: pitch, onset: Double(i), offset: Double(i) + (duration ?? 0.9), onsetBeats: Double(i))
            }
            return MIDISequence(notes: notes, initialTempoBPM: 60, timeSignature: .common)
        }
        let reference = sequence(duration: nil)
        for duration in [0.05, 0.4, 3.0] {
            let report = Grader().grade(reference: reference, take: sequence(duration: duration))
            XCTAssertTrue(report.passed, "notes \(duration) s long")
            XCTAssertEqual(report.notes.correct, 9)
            XCTAssertTrue(report.flags.isEmpty, "notes \(duration) s long: \(report.flags.map(\.message))")
        }
    }
}
