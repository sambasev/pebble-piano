import XCTest
import PianoGraderCore
@testable import PianoLessons

final class GremlinTests: XCTestCase {
    private func ts(_ n: Int, _ d: Int) -> TimeSignature { TimeSignature(numerator: n, denominator: d) }

    // MARK: Meter

    func testSimpleMetersCountTheirDenominator() {
        XCTAssertEqual(GremlinMeter(ts(4, 4)), GremlinMeter(beatsPerBar: 4, quartersPerBeat: 1))
        XCTAssertEqual(GremlinMeter(ts(3, 4)), GremlinMeter(beatsPerBar: 3, quartersPerBeat: 1))
        XCTAssertEqual(GremlinMeter(ts(2, 2)), GremlinMeter(beatsPerBar: 2, quartersPerBeat: 2))
        XCTAssertEqual(GremlinMeter(ts(3, 8)), GremlinMeter(beatsPerBar: 3, quartersPerBeat: 0.5), "3/8 is felt in three")
    }

    func testCompoundMetersAreFeltInDottedBeats() {
        XCTAssertEqual(GremlinMeter(ts(6, 8)), GremlinMeter(beatsPerBar: 2, quartersPerBeat: 1.5))
        XCTAssertEqual(GremlinMeter(ts(9, 8)), GremlinMeter(beatsPerBar: 3, quartersPerBeat: 1.5))
        XCTAssertEqual(GremlinMeter(ts(12, 8)), GremlinMeter(beatsPerBar: 4, quartersPerBeat: 1.5))
        XCTAssertEqual(GremlinMeter(ts(6, 8)).quartersPerBar, 3)
    }

    // MARK: Beat

    func testBeatInFourFour() {
        let m = GremlinMeter.common
        let b = GremlinBeat.at(quarter: 6.25, barStart: 0, meter: m)
        XCTAssertEqual(b.bar, 1)
        XCTAssertEqual(b.beat, 2)
        XCTAssertEqual(b.phase, 0.25, accuracy: 1e-9)
        XCTAssertEqual(b.beatTime, 6.25, accuracy: 1e-9)
    }

    func testBeatInThreeFourAndSixEight() {
        let three = GremlinBeat.at(quarter: 5, bar: 1, barStart: 3, meter: GremlinMeter(ts(3, 4)))
        XCTAssertEqual(three.bar, 1)
        XCTAssertEqual(three.beat, 2)
        XCTAssertTrue(three.isLastBeat)

        let six = GremlinBeat.at(quarter: 2.25, barStart: 0, meter: GremlinMeter(ts(6, 8)))
        XCTAssertEqual(six.beat, 1, "the second dotted beat starts at 1.5 quarters")
        XCTAssertEqual(six.phase, 0.5, accuracy: 1e-9)
    }

    func testCountInIsBeforeTheFirstBar() {
        let b = GremlinBeat.at(quarter: -1, barStart: 0, meter: .common)
        XCTAssertEqual(b.bar, -1)
        XCTAssertEqual(b.beat, 3, "the last count-in beat")
        XCTAssertEqual(b.beatTime, -1, accuracy: 1e-9)
    }

    func testPickupBarIsTheEndOfABar() {
        // A one-beat upbeat in 4/4: it's beat 4, so the big jump lands on bar 1's downbeat.
        let up = GremlinBeat.at(quarter: 0.5, bar: 0, barStart: 0, barLength: 1, pickup: true, meter: .common)
        XCTAssertEqual(up.beat, 3)
        XCTAssertTrue(up.isLastBeat)
        let down = GremlinBeat.at(quarter: 1, bar: 1, barStart: 1, meter: .common)
        XCTAssertTrue(down.isDownbeat)
        XCTAssertEqual(down.beatTime - up.beatTime, 0.5, accuracy: 1e-9, "beat time runs on smoothly")
    }

    // MARK: Pose

    func testBigJumpOnTheLastBeatSmallBobsOtherwise() {
        let m = GremlinMeter(ts(3, 4))
        let bob = GremlinPose.dancing(GremlinBeat.at(quarter: 0.5, barStart: 0, meter: m))
        let jump = GremlinPose.dancing(GremlinBeat.at(quarter: 2.5, barStart: 0, meter: m))
        XCTAssertEqual(bob.lift, GremlinPose.beatHop, accuracy: 1e-9)
        XCTAssertEqual(jump.lift, GremlinPose.barJump, accuracy: 1e-9)
        XCTAssertGreaterThan(jump.lift, bob.lift * 3)
    }

    func testLandsSquashedHardestOnTheDownbeat() {
        let m = GremlinMeter.common
        let downbeat = GremlinPose.dancing(GremlinBeat.at(quarter: 4, barStart: 0, meter: m))
        let beatTwo = GremlinPose.dancing(GremlinBeat.at(quarter: 5, barStart: 0, meter: m))
        XCTAssertEqual(downbeat.lift, 0, accuracy: 1e-9, "on the ground on the beat")
        XCTAssertLessThan(downbeat.stretch, beatTwo.stretch)
        XCTAssertLessThan(beatTwo.stretch, 0)
    }

    func testOneBeatBarsJumpEveryBeat() {
        let m = GremlinMeter(beatsPerBar: 1, quartersPerBeat: 1)
        let pose = GremlinPose.dancing(GremlinBeat.at(quarter: 7.5, barStart: 0, meter: m))
        XCTAssertEqual(pose.lift, GremlinPose.barJump, accuracy: 1e-9)
    }

    // MARK: Reactions

    func testCheerHopsThenEnds() {
        let r = GremlinReaction(kind: .cheer, startedAt: 10)
        let mid = r.apply(to: .rest, at: 10 + GremlinReaction.cheerSeconds / 2)
        XCTAssertGreaterThan(mid.lift, 0.2)
        XCTAssertEqual(mid.face, .happy)
        XCTAssertEqual(r.apply(to: .rest, at: 9.9), .rest, "not yet")
        XCTAssertEqual(r.apply(to: .rest, at: 12), .rest, "over")
    }

    func testOopsWobblesWithAWorriedFace() {
        let r = GremlinReaction(kind: .oops, startedAt: 0)
        let p = r.apply(to: .rest, at: 0.1)
        XCTAssertEqual(p.face, .worried)
        XCTAssertNotEqual(p.tilt, 0)
        XCTAssertEqual(r.apply(to: .rest, at: 0.1, delay: 0.2), .rest, "a later dancer hasn't started")
    }

    // MARK: Wandering

    func testWanderStaysInItsLaneAndIsRepeatable() {
        let w = GremlinWander.dancer(1)
        for i in 0..<2000 {
            let t = Double(i) * 0.37 - 100
            let a = w.position(atBeat: t), b = w.position(atBeat: t)
            XCTAssertEqual(a.x, b.x)
            XCTAssertLessThanOrEqual(abs(a.x), 1)
            XCTAssertTrue(a.facing == 1 || a.facing == -1)
        }
    }

    func testWalksStartAndStopOnWholeBeats() {
        let w = GremlinWander.dancer(0)
        for leg in 0..<50 {
            let start = Double(leg * w.legBeats)
            let rest = Double(w.restBeats(leg))
            XCTAssertTrue((2...4).contains(Int(rest)))
            // Standing still for the rest beats, then moving.
            XCTAssertEqual(w.position(atBeat: start + 0.01).x, w.position(atBeat: start + rest - 0.01).x, accuracy: 1e-9)
            // Arrives as the leg ends: no jump into the next leg.
            let end = start + Double(w.legBeats)
            XCTAssertEqual(w.position(atBeat: end - 1e-6).x, w.position(atBeat: end).x, accuracy: 1e-4)
        }
    }

    func testDancersMoveOutOfStep() {
        XCTAssertNotEqual(GremlinWander.dancer(0).legBeats, GremlinWander.dancer(1).legBeats)
        XCTAssertNotEqual(GremlinWander.dancer(0).position(atBeat: 20).x, GremlinWander.dancer(1).position(atBeat: 20).x)
    }

    func testWalkClockFollowsTheMusicAndSurvivesJumps() {
        var clock = GremlinWalkClock()
        clock.advance(toBeat: 0.25)
        XCTAssertEqual(clock.time, 0.25, accuracy: 1e-9)
        clock.advance(toBeat: 0.75)
        XCTAssertEqual(clock.time, 0.75, accuracy: 1e-9)
        // A bar replays: the music jumps back four beats; the stroll doesn't.
        clock.advance(toBeat: -3.1)
        XCTAssertGreaterThanOrEqual(clock.time, 0.75)
        XCTAssertEqual(clock.time - clock.time.rounded(.down), 0.9, accuracy: 1e-9, "keeps the beat's fraction")
        // Nothing playing: holds still.
        let held = clock.time
        clock.advance(toBeat: nil)
        XCTAssertEqual(clock.time, held)
    }
}
