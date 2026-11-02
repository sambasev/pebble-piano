import XCTest
@testable import PianoGraderCore

/// Builds a sequence from (pitch or chord, beat in quarter notes) at a tempo.
private func sequence(_ events: [([Int], Double)], bpm: Double = 60, ts: TimeSignature = .common) -> MIDISequence {
    let spq = 60.0 / bpm
    var notes: [NoteEvent] = []
    for (pitches, beat) in events {
        for p in pitches {
            notes.append(NoteEvent(pitch: p, onset: beat * spq, offset: (beat + 0.9) * spq, onsetBeats: beat))
        }
    }
    return MIDISequence(notes: notes, initialTempoBPM: bpm, timeSignature: ts)
}

/// C D E F G F E D C, one note per beat, as in a first five-finger exercise.
private let fiveFinger: [([Int], Double)] = [60, 62, 64, 65, 67, 65, 64, 62, 60].enumerated().map { ([$0.element], Double($0.offset)) }

final class GraderTests: XCTestCase {
    private var reference: MIDISequence { sequence(fiveFinger) }

    func testCleanTakePasses() {
        let report = Grader().grade(reference: reference, take: sequence(fiveFinger))
        XCTAssertTrue(report.passed)
        XCTAssertEqual(report.notes.correct, 9)
        XCTAssertEqual(report.notes.score, 1, accuracy: 1e-9)
        XCTAssertTrue(report.flags.isEmpty)
        XCTAssertEqual(report.timing?.fittedBPM ?? 0, 60, accuracy: 0.01)
    }

    func testWrongNoteIsReportedAsWrongPitchAtItsPosition() {
        var take = fiveFinger
        take[1] = ([64], 1) // E instead of D on beat 2
        let report = Grader().grade(reference: reference, take: sequence(take))
        XCTAssertEqual(report.notes.wrongPitch, 1)
        XCTAssertEqual(report.notes.missed, 0)
        XCTAssertEqual(report.notes.extra, 0)
        XCTAssertFalse(report.passed) // 8/9 = 89% < 95%
        let flag = try? XCTUnwrap(report.flags.first)
        XCTAssertEqual(flag?.kind, .wrongPitch)
        XCTAssertEqual(flag?.message, "m1 b2: played E4, expected D4")
    }

    func testSkippedNoteIsMissed() {
        var take = fiveFinger
        take.remove(at: 4) // skip the G
        let report = Grader().grade(reference: reference, take: sequence(take))
        XCTAssertEqual(report.notes.missed, 1)
        XCTAssertEqual(report.notes.correct, 8)
        XCTAssertEqual(report.flags.first?.message, "m2 b1: missed G4")
    }

    func testSkippedBarIsMissedWhereItWasEvenWhenItsNotesRepeat() {
        // Bar 2 ends E G, and bar 3 (skipped) repeats them: the take's E G are bar 2's, played
        // in time, so only bar 3 is missed.
        let bars: [[Int]] = [[60, 62, 64, 65], [60, 62, 64, 67], [64, 67, 64, 67], [60, 60, 60, 60]]
        let events = bars.enumerated().flatMap { bar, pitches in
            pitches.enumerated().map { ([$0.element], Double(bar * 4 + $0.offset)) }
        }
        let take = events.filter { $0.1 < 8 || $0.1 >= 12 }
        let report = Grader().grade(reference: sequence(events), take: sequence(take))
        XCTAssertEqual(report.notes.missed, 4)
        XCTAssertEqual(Set(report.results.filter { $0.kind == .missed }.map(\.position.measure)), [3])
    }

    func testExtraNoteInTheMiddleIsPenalised() {
        var take = fiveFinger
        take.insert(([66], 4.5), at: 5) // stray F# between G and F
        let report = Grader().grade(reference: reference, take: sequence(take))
        XCTAssertEqual(report.notes.extra, 1)
        XCTAssertEqual(report.notes.correct, 9)
        XCTAssertEqual(report.notes.score, (9 - 0.5) / 9, accuracy: 1e-9)
        XCTAssertTrue(report.flags.contains { $0.kind == .extra })
    }

    func testWarmUpNotesBeforeThePassageAreIgnored() {
        let take = [([48], -3.0), ([50], -2.0)] + fiveFinger
        let report = Grader().grade(reference: reference, take: sequence(take))
        XCTAssertEqual(report.notes.ignoredLeading, 2)
        XCTAssertEqual(report.notes.extra, 0)
        XCTAssertTrue(report.passed)
    }

    func testChordWithOneWrongNote() {
        let ref = sequence([([60, 64, 67], 0), ([62, 65, 69], 1), ([64, 67, 72], 2), ([60, 64, 67], 3)])
        let take = sequence([([60, 64, 67], 0), ([62, 65, 70], 1), ([64, 67, 72], 2), ([60, 64, 67], 3)])
        let report = Grader().grade(reference: ref, take: take)
        XCTAssertEqual(report.notes.correct, 11)
        XCTAssertEqual(report.notes.wrongPitch, 1)
        XCTAssertEqual(report.flags.first?.message, "m1 b2: played A#4, expected A4")
    }

    func testUniformlySlowTakePassesRhythmButFailsTempoWhenGraded() {
        var rubric = Rubric()
        rubric.checks = [.notes, .rhythm, .tempo]
        let report = Grader(rubric: rubric).grade(reference: reference, take: sequence(fiveFinger, bpm: 45))
        let rhythm = report.levels.first { $0.check == .rhythm }
        let tempo = report.levels.first { $0.check == .tempo }
        XCTAssertEqual(rhythm?.passed, true)
        XCTAssertEqual(tempo?.passed, false)
        XCTAssertEqual(report.timing?.fittedBPM ?? 0, 45, accuracy: 0.01)
        XCTAssertFalse(report.passed)
    }

    func testBeginnerRubricDoesNotGradeTempo() {
        let report = Grader().grade(reference: reference, take: sequence(fiveFinger, bpm: 45))
        XCTAssertNil(report.levels.first { $0.check == .tempo }?.passed)
        XCTAssertTrue(report.passed)
    }

    func testRushedNoteIsFlaggedOnceAsEarly() {
        var take = fiveFinger
        take[4] = ([67], 3.4) // G comes in at beat 3.4 instead of 4
        let report = Grader().grade(reference: reference, take: sequence(take))
        let timingFlags = report.flags.filter { $0.kind == .early || $0.kind == .late }
        XCTAssertEqual(timingFlags.count, 1)
        XCTAssertEqual(timingFlags.first?.kind, .early)
        XCTAssertEqual(timingFlags.first?.position.label, "m2 b1")
    }

    func testRhythmFailsWhenManyIntervalsAreWrong() {
        // Every other note held twice as long.
        let take: [([Int], Double)] = [0, 2, 3, 5, 6, 8, 9, 11, 12].enumerated().map { ([fiveFinger[$0.offset].0[0]], Double($0.element)) }
        let report = Grader().grade(reference: reference, take: sequence(take))
        XCTAssertEqual(report.levels.first { $0.check == .rhythm }?.passed, false)
        XCTAssertFalse(report.passed)
    }

    func testScorePositionInThreeFour() {
        let ts = TimeSignature(numerator: 3, denominator: 4)
        XCTAssertEqual(ScorePosition(quarters: 0, timeSignature: ts).label, "m1 b1")
        XCTAssertEqual(ScorePosition(quarters: 4, timeSignature: ts).label, "m2 b2")
        XCTAssertEqual(ScorePosition(quarters: 4.5, timeSignature: ts).label, "m2 b2.5")
    }

    func testSixEightBeatsAreEighths() {
        let ts = TimeSignature(numerator: 6, denominator: 8)
        XCTAssertEqual(ScorePosition(quarters: 3, timeSignature: ts).label, "m2 b1")
        XCTAssertEqual(ScorePosition(quarters: 1, timeSignature: ts).label, "m1 b3")
    }
}

final class AlignerTests: XCTestCase {
    private func chords(_ pitches: [Int]) -> [ChordEvent] {
        pitches.enumerated().map { ChordEvent(notes: [NoteEvent(pitch: $0.element, onset: Double($0.offset), offset: Double($0.offset) + 0.5)]) }
    }

    func testIdenticalSequencesPairOneToOne() {
        let steps = Aligner.align(reference: chords([60, 62, 64]), performance: chords([60, 62, 64]))
        XCTAssertEqual(steps, [.pair(ref: 0, perf: 0), .pair(ref: 1, perf: 1), .pair(ref: 2, perf: 2)])
    }

    func testSubstitutionBeatsTwoGaps() {
        let steps = Aligner.align(reference: chords([60, 62, 64]), performance: chords([60, 63, 64]))
        XCTAssertEqual(steps, [.pair(ref: 0, perf: 0), .pair(ref: 1, perf: 1), .pair(ref: 2, perf: 2)])
    }

    func testSkippedNoteBecomesRefOnly() {
        let steps = Aligner.align(reference: chords([60, 62, 64, 65]), performance: chords([60, 64, 65]))
        XCTAssertEqual(steps, [.pair(ref: 0, perf: 0), .refOnly(1), .pair(ref: 2, perf: 1), .pair(ref: 3, perf: 2)])
    }

    func testEmptyPerformance() {
        let steps = Aligner.align(reference: chords([60, 62]), performance: [])
        XCTAssertEqual(steps, [.refOnly(0), .refOnly(1)])
    }
}

final class MIDIFileTests: XCTestCase {
    func testWriteThenReadRoundTrips() throws {
        let notes = [
            NoteEvent(pitch: 60, onset: 0, offset: 0.5, velocity: 70),
            NoteEvent(pitch: 64, onset: 0, offset: 0.5, velocity: 72),
            NoteEvent(pitch: 62, onset: 0.5, offset: 1.0, velocity: 90),
            NoteEvent(pitch: 62, onset: 1.0, offset: 1.5, velocity: 90), // repeated note
        ]
        let data = MIDIFile.write(notes: notes, tempoBPM: 120, timeSignature: TimeSignature(numerator: 3, denominator: 4))
        let seq = try MIDIFile.parse(data)
        XCTAssertEqual(seq.notes.map(\.pitch), [60, 64, 62, 62])
        XCTAssertEqual(seq.initialTempoBPM, 120, accuracy: 0.01)
        XCTAssertEqual(seq.timeSignature, TimeSignature(numerator: 3, denominator: 4))
        for (a, b) in zip(seq.notes, notes) {
            XCTAssertEqual(a.onset, b.onset, accuracy: 0.002)
            XCTAssertEqual(a.offset, b.offset, accuracy: 0.002)
            XCTAssertEqual(a.velocity, b.velocity)
        }
        XCTAssertEqual(seq.notes[2].onsetBeats, 1, accuracy: 1e-9) // 0.5 s at 120 bpm
    }

    func testRunningStatusAndNoteOnVelocityZero() throws {
        // Format 0, 96 ppq: note on C4, (running status) note on C4 vel 0 after one quarter.
        var bytes: [UInt8] = Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0, 96]
        let track: [UInt8] = [0x00, 0x90, 60, 100, 0x60, 60, 0, 0x00, 0xFF, 0x2F, 0x00]
        bytes += Array("MTrk".utf8) + [0, 0, 0, UInt8(track.count)] + track
        let seq = try MIDIFile.parse(Data(bytes))
        XCTAssertEqual(seq.notes.count, 1)
        XCTAssertEqual(seq.notes[0].offset, 0.5, accuracy: 1e-9) // default 120 bpm
    }

    func testRejectsNonMIDI() {
        XCTAssertThrowsError(try MIDIFile.parse(Data("hello world, not midi".utf8)))
    }
}

final class RubricTests: XCTestCase {
    func testMarkdownFrontMatterWithDefaults() throws {
        let text = """
        ---
        level: intermediate
        checks: [notes, rhythm, tempo]
        notes:
          min_accuracy: 0.9
        tempo:
          tolerance: 0.1
        ---
        Mention at most one rhythm issue per attempt.
        """
        let rubric = try Rubric.parse(text)
        XCTAssertEqual(rubric.level, "intermediate")
        XCTAssertEqual(rubric.checks, [.notes, .rhythm, .tempo])
        XCTAssertEqual(rubric.notes.minAccuracy, 0.9)
        XCTAssertEqual(rubric.notes.extraNotePenalty, 0.5) // default kept
        XCTAssertEqual(rubric.tempo.tolerance, 0.1)
        XCTAssertEqual(rubric.rhythm.maxMeanIOIError, 0.25)
        XCTAssertEqual(rubric.guidance, "Mention at most one rhythm issue per attempt.")
    }

    func testPlainYAML() throws {
        let rubric = try Rubric.parse("chord_window_ms: 80\ntarget_bpm: 72\n")
        XCTAssertEqual(rubric.chordWindowMs, 80)
        XCTAssertEqual(rubric.targetBPM, 72)
        XCTAssertEqual(rubric.checks, [.notes, .rhythm])
    }
}
