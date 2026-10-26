import XCTest
@testable import PianoGraderCore

final class BeatClockTests: XCTestCase {
    func testAudioTimeAndBarsAt4_4() {
        let clock = BeatClock(startSeconds: 2, bpm: 120)          // 0.5 s per quarter
        XCTAssertEqual(clock.audioSeconds(atQuarter: 0), 2, accuracy: 1e-9)
        XCTAssertEqual(clock.audioSeconds(atQuarter: 4), 4, accuracy: 1e-9)
        XCTAssertEqual(clock.quarter(atAudioSeconds: 3), 2, accuracy: 1e-9)
        XCTAssertEqual(clock.barIndex(containing: 0), 0)
        XCTAssertEqual(clock.barIndex(containing: 3.99), 0)
        XCTAssertEqual(clock.barIndex(containing: 4), 1)
        XCTAssertEqual(clock.barIndex(containing: -1), 0)
        XCTAssertEqual(clock.barStart(3), 12, accuracy: 1e-9)
    }

    func testTempoFactorChangesRealTimeOnly() {
        var clock = BeatClock(bpm: 120)
        XCTAssertEqual(clock.secondsPerQuarter, 0.5, accuracy: 1e-9)
        clock.tempoFactor = 0.5
        XCTAssertEqual(clock.secondsPerQuarter, 1.0, accuracy: 1e-9)
        XCTAssertEqual(clock.audioSeconds(atQuarter: 4), 2, accuracy: 1e-9) // the recording is unchanged
    }

    func testPickupBarThenFullBars() {
        // A one-beat pickup in 3/4, then two listed bars; later bars are full 3/4 bars.
        let clock = BeatClock(bpm: 90, timeSignature: TimeSignature(numerator: 3, denominator: 4), barLengths: [1, 3, 3])
        XCTAssertEqual(clock.barIndex(containing: 0.5), 0)
        XCTAssertEqual(clock.barIndex(containing: 1), 1)
        XCTAssertEqual(clock.barIndex(containing: 3.9), 1)
        XCTAssertEqual(clock.barIndex(containing: 4), 2)
        XCTAssertEqual(clock.barIndex(containing: 7), 3)
        XCTAssertEqual(clock.barStart(3), 7, accuracy: 1e-9)
        XCTAssertEqual(clock.barStart(4), 10, accuracy: 1e-9)
        XCTAssertEqual(clock.barLength(0), 1, accuracy: 1e-9)
    }

    func testAnchorMapsUptimeToQuarters() {
        let anchor = PlaybackAnchor(uptime: 100, quarter: 8, secondsPerQuarter: 0.5)
        XCTAssertEqual(anchor.quarter(atUptime: 101), 10, accuracy: 1e-9)
        XCTAssertEqual(anchor.quarter(atUptime: 99), 6, accuracy: 1e-9)   // count-in: before the bar
        XCTAssertEqual(anchor.uptime(atQuarter: 12), 102, accuracy: 1e-9)
    }
}

final class BackingAnnotationTests: XCTestCase {
    func testDecodesAPassageWithBacking() throws {
        let json = """
        { "id": "p", "title": "t", "page": 1, "reference": "r.mid",
          "box": { "x": 0, "y": 0, "width": 1, "height": 1 }, "measures": [],
          "backing": { "file": "b.m4a", "startSeconds": 1.84, "bpm": 92, "timeSignature": "3/4",
                       "key": "Bbm", "countInBars": 2 } }
        """
        let passage = try JSONDecoder().decode(PassageAnnotation.self, from: Data(json.utf8))
        let backing = try XCTUnwrap(passage.backing)
        XCTAssertEqual(backing.file, "b.m4a")
        XCTAssertEqual(backing.startSeconds, 1.84)
        XCTAssertEqual(backing.bpm, 92)
        XCTAssertEqual(backing.timeSignature, TimeSignature(numerator: 3, denominator: 4))
        XCTAssertEqual(backing.countInBars, 2)
        XCTAssertEqual(backing.keySignature, KeySignature(fifths: -5, isMinor: true))
        // Round trip keeps the "3/4" form.
        let again = try JSONDecoder().decode(BackingAnnotation.self, from: JSONEncoder().encode(backing))
        XCTAssertEqual(again, backing)
    }

    func testPassageWithoutBackingStillDecodes() throws {
        let json = """
        { "id": "p", "title": "t", "page": 1, "reference": "r.mid",
          "box": { "x": 0, "y": 0, "width": 1, "height": 1 }, "measures": [] }
        """
        XCTAssertNil(try JSONDecoder().decode(PassageAnnotation.self, from: Data(json.utf8)).backing)
    }

    func testRejectsBadTimeSignature() {
        let json = #"{ "file": "b.m4a", "bpm": 92, "timeSignature": "4" }"#
        XCTAssertThrowsError(try JSONDecoder().decode(BackingAnnotation.self, from: Data(json.utf8)))
    }

    func testKeyNames() {
        XCTAssertEqual(KeySignature(name: "C"), KeySignature(fifths: 0))
        XCTAssertEqual(KeySignature(name: "F#"), KeySignature(fifths: 6))
        XCTAssertEqual(KeySignature(name: "eb major"), KeySignature(fifths: -3))
        XCTAssertEqual(KeySignature(name: "Am"), KeySignature(fifths: 0, isMinor: true))
        XCTAssertEqual(KeySignature(name: "C# minor"), KeySignature(fifths: 4, isMinor: true))
        XCTAssertNil(KeySignature(name: "H"))
    }

    func testRubricPlayAlongSection() throws {
        let rubric = try Rubric.parse("""
        ---
        play_along:
          late_ms: 300
          max_misses_per_bar: 1
        ---
        """)
        XCTAssertEqual(rubric.playAlong.lateMs, 300)
        XCTAssertEqual(rubric.playAlong.maxMissesPerBar, 1)
        XCTAssertEqual(rubric.playAlong.earlyMs, 250)              // default kept
        let mic = rubric.playAlong.judgeSettings(microphone: true)
        XCTAssertEqual(mic.lateSeconds, 0.42, accuracy: 1e-9)       // 300 + 120 ms
    }
}

final class PitchSetTests: XCTestCase {
    func testBasics() {
        var s = PitchSet([60, 64, 127, 0])
        XCTAssertTrue(s.contains(60) && s.contains(127) && s.contains(0))
        XCTAssertFalse(s.contains(61))
        XCTAssertEqual(s.count, 4)
        s.remove(127)
        s.insert(200)                                 // ignored
        XCTAssertEqual(s.sorted, [0, 60, 64])
        XCTAssertTrue(s.isSuperset(of: PitchSet([60, 64])))
        XCTAssertEqual(s.subtracting(PitchSet([60])).sorted, [0, 64])
    }
}

final class PlayAlongJudgeTests: XCTestCase {
    // 120 bpm, 4/4: 0.5 s per quarter. Default windows: 0.25 s early (0.5 q), 0.4 s late (0.8 q).
    let clock = BeatClock(bpm: 120)

    /// One note per quarter for `bars` bars: C D E F, C D E F…
    func scale(bars: Int) -> [(quarter: Double, pitches: Set<Int>)] {
        (0..<(bars * 4)).map { (quarter: Double($0), pitches: [[60, 62, 64, 65][$0 % 4]]) }
    }

    func testPlayingInTimeCarriesOnToTheEnd() {
        var j = PlayAlongJudge(chords: scale(bars: 2), clock: clock)
        XCTAssertEqual(j.endQuarter, 8)
        for i in 0..<8 {
            j.noteOn([60, 62, 64, 65][i % 4], atQuarter: Double(i) + 0.2)
            XCTAssertEqual(j.advance(toQuarter: Double(i) + 0.5), .onTrack)
        }
        XCTAssertEqual(j.advance(toQuarter: 8.9), .finished)
        XCTAssertTrue(j.states.allSatisfy { $0 == .hit })
    }

    func testOneMissInABarOfFourIsForgiven() {
        var j = PlayAlongJudge(chords: scale(bars: 2), clock: clock)
        j.noteOn(60, atQuarter: 0)
        // D at quarter 1 is skipped.
        j.noteOn(64, atQuarter: 2)
        j.noteOn(65, atQuarter: 3)
        XCTAssertEqual(j.advance(toQuarter: 4), .onTrack)
        XCTAssertEqual(j.states[1], .missed)
        XCTAssertEqual(j.barMisses[0], 1)
        XCTAssertEqual(j.allowedMisses(inBar: 0), 1)                // ⌊4 × 0.34⌋
    }

    func testTwoMissesInABarRewindsToThatBar() {
        var j = PlayAlongJudge(chords: scale(bars: 2), clock: clock)
        for i in 0..<4 { j.noteOn([60, 62, 64, 65][i], atQuarter: Double(i)) }
        XCTAssertEqual(j.advance(toQuarter: 4.5), .onTrack)
        j.noteOn(60, atQuarter: 4)
        // D (5) missed, E (6) played, F (7) missed.
        j.noteOn(64, atQuarter: 6.1)
        XCTAssertEqual(j.advance(toQuarter: 7.5), .onTrack)         // F's window is still open
        XCTAssertEqual(j.advance(toQuarter: 7.9), .rewind(bar: 1))
    }

    func testLateButInsideTheWindowCounts() {
        var j = PlayAlongJudge(chords: scale(bars: 1), clock: clock)
        j.noteOn(60, atQuarter: 0.75)                              // 0.375 s late, window 0.4 s
        XCTAssertEqual(j.advance(toQuarter: 1), .onTrack)
        XCTAssertEqual(j.states[0], .hit)
    }

    func testTooLateIsAMissAndAnExtra() {
        var lax = PlayAlongJudge.Settings()
        lax.maxMissFraction = 1
        lax.maxMissesPerBar = 4
        var j = PlayAlongJudge(chords: [(quarter: 0, pitches: [60]), (quarter: 2, pitches: [67])], clock: clock, settings: lax)
        XCTAssertEqual(j.advance(toQuarter: 0.9), .onTrack)         // C missed (allowed here)
        j.noteOn(60, atQuarter: 1.0)                               // too late: matches nothing
        XCTAssertEqual(j.states[0], .missed)
        XCTAssertEqual(j.extraNotes, 1)
    }

    func testWrongNotesNeverStopTheMusic() {
        var j = PlayAlongJudge(chords: scale(bars: 1), clock: clock)
        for i in 0..<4 {
            j.noteOn([60, 62, 64, 65][i], atQuarter: Double(i))
            j.noteOn(71, atQuarter: Double(i) + 0.1)                // a wrong key every beat
        }
        XCTAssertEqual(j.advance(toQuarter: 4.9), .finished)
        XCTAssertEqual(j.extraNotes, 4)
    }

    func testStoppingRewindsToWhereItStarted() {
        // Bars forgive any number of misses here, so only the consecutive rule can rewind.
        var settings = PlayAlongJudge.Settings()
        settings.maxMissFraction = 1
        settings.maxMissesPerBar = 4
        settings.maxConsecutiveMisses = 3
        var j = PlayAlongJudge(chords: scale(bars: 3), clock: clock, settings: settings)
        for i in 0..<3 { j.noteOn([60, 62, 64, 65][i], atQuarter: Double(i)) }
        // Player stops after quarter 2: misses at 3, 4, 5.
        XCTAssertEqual(j.advance(toQuarter: 4.9), .onTrack)
        XCTAssertEqual(j.advance(toQuarter: 5.9), .rewind(bar: 0))  // the run started in bar 0
    }

    func testASingleMissedWholeNoteFailsItsBar() {
        let chords = (0..<3).map { (quarter: Double($0 * 4), pitches: Set([60])) }
        var j = PlayAlongJudge(chords: chords, clock: clock)
        j.noteOn(60, atQuarter: 0)
        XCTAssertEqual(j.advance(toQuarter: 4.9), .rewind(bar: 1))
    }

    func testRepeatedNotesAreMatchedOneByOne() {
        let chords = (0..<4).map { (quarter: Double($0) * 0.5, pitches: Set([60])) } // eighth notes
        var j = PlayAlongJudge(chords: chords, clock: clock)
        for i in 0..<4 { j.noteOn(60, atQuarter: Double(i) * 0.5 + 0.05) }
        XCTAssertTrue(j.states.allSatisfy { $0 == .hit })
        XCTAssertEqual(j.extraNotes, 0)
    }

    func testChordCoverage() {
        var j = PlayAlongJudge(chords: [(quarter: 0, pitches: [60, 64, 67, 72])], clock: clock)
        j.noteOn(60, atQuarter: 0)
        XCTAssertEqual(j.states[0], .pending)
        j.noteOn(64, atQuarter: 0.02)                              // 2 of 4 = 50 %
        XCTAssertEqual(j.states[0], .hit)
        XCTAssertEqual(j.expected.sorted, [])                      // nothing after it
    }

    func testRewindForgetsTheBarAndAfterButKeepsEarlierBars() {
        var j = PlayAlongJudge(chords: scale(bars: 2), clock: clock)
        for i in 0..<4 { j.noteOn([60, 62, 64, 65][i], atQuarter: Double(i)) }
        XCTAssertEqual(j.advance(toQuarter: 6.9), .rewind(bar: 1))  // bar 1 untouched: 2 missed
        j.rewind(toBar: 1)
        XCTAssertEqual(j.startBar, 1)
        XCTAssertEqual(j.barMisses[1], 0)
        XCTAssertTrue(j.states[0..<4].allSatisfy { $0 == .hit })
        XCTAssertTrue(j.states[4..<8].allSatisfy { $0 == .pending })
        XCTAssertEqual(j.expected.sorted, [60])
        // Count-in (quarters 0–4 replayed as lead-in) doesn't touch bar 0.
        j.noteOn(60, atQuarter: 2)
        XCTAssertEqual(j.states[0], .hit)
        for i in 4..<8 { j.noteOn([60, 62, 64, 65][i % 4], atQuarter: Double(i)) }
        XCTAssertEqual(j.advance(toQuarter: 8.9), .finished)
    }

    func testSlowerTempoWidensTheWindowInQuarters() {
        var j = PlayAlongJudge(chords: scale(bars: 1), clock: clock)
        var slow = clock
        slow.tempoFactor = 0.5                                     // 1 s per quarter
        j.configure(settings: PlayAlongJudge.Settings(), secondsPerQuarter: slow.secondsPerQuarter)
        j.noteOn(60, atQuarter: 0.39)                              // 0.39 s late
        XCTAssertEqual(j.states[0], .hit)
        XCTAssertEqual(j.advance(toQuarter: 0.41), .onTrack)       // C hit; D not due yet
    }

    func testWaitingOnTheChordThatTippedTheBarThenCarryingOn() {
        var j = PlayAlongJudge(chords: scale(bars: 2), clock: clock)
        j.noteOn(60, atQuarter: 0)
        // D and E missed: the second miss fails bar 0.
        XCTAssertEqual(j.advance(toQuarter: 2.9), .rewind(bar: 0))
        XCTAssertEqual(j.lastMissedChord, 2)
        j.waitOn(chord: 2)
        XCTAssertEqual(j.states[2], .pending)
        XCTAssertEqual(j.barMisses[0], 1)                         // D's miss still counts
        XCTAssertEqual(j.expected.sorted, [64])
        // Played late, at its own time while the music is stopped: it counts.
        XCTAssertTrue(j.noteOn(64, atQuarter: 2))
        XCTAssertEqual(j.states[2], .hit)
        // The music resumes from E; F comes on time.
        j.noteOn(65, atQuarter: 3)
        XCTAssertEqual(j.advance(toQuarter: 3.5), .onTrack)
    }
}
