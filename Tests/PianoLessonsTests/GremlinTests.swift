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
            let start = Double(leg * w.legBeats) - w.offsetBeats
            let rest = Double(w.restBeats(leg)), walk = Double(w.walkBeats(leg))
            XCTAssertGreaterThanOrEqual(rest, 2)
            XCTAssertLessThanOrEqual(rest + walk, Double(w.legBeats))
            // Standing for the rest beats, then walking, then standing again until the leg ends.
            XCTAssertEqual(w.position(atBeat: start + 0.01).x, w.position(atBeat: start + rest - 0.01).x, accuracy: 1e-9)
            let end = start + Double(w.legBeats)
            XCTAssertEqual(w.position(atBeat: start + rest + walk).x, w.position(atBeat: end - 0.01).x, accuracy: 1e-9)
            // No jump into the next leg.
            XCTAssertEqual(w.position(atBeat: end - 1e-6).x, w.position(atBeat: end).x, accuracy: 1e-4)
        }
    }

    func testEveryoneWalksAtTheSameSlowPace() {
        let dancers = (0..<3).map { GremlinWander.dancer($0) }
        XCTAssertEqual(Set(dancers.map(\.speed)).count, 1, "one pace for everyone")
        for w in dancers {
            var fastest = 0.0
            var t = 0.0
            while t < 400 {
                let a = w.position(atBeat: t).x, b = w.position(atBeat: t + 0.05).x
                fastest = max(fastest, abs(b - a) / 0.05)
                t += 0.05
            }
            // Easing in and out keeps the top speed a little above the average pace.
            XCTAssertLessThanOrEqual(fastest, GremlinWander.walkingSpeed * 1.8)
            XCTAssertGreaterThan(fastest, 0, "they do stroll")
        }
    }

    func testStrideEasesInAndOut() {
        XCTAssertEqual(GremlinWander.stride(0, rampFraction: 0.2), 0, accuracy: 1e-12)
        XCTAssertEqual(GremlinWander.stride(1, rampFraction: 0.2), 1, accuracy: 1e-12)
        XCTAssertEqual(GremlinWander.stride(0.5, rampFraction: 0.2), 0.5, accuracy: 1e-12)
        XCTAssertLessThan(GremlinWander.stride(0.05, rampFraction: 0.2), 0.05, "slow to start")
    }

    func testDancersMoveOutOfStep() {
        XCTAssertNotEqual(GremlinWander.dancer(0).offsetBeats, GremlinWander.dancer(1).offsetBeats)
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

    // MARK: Walking with steps

    /// A body walking right from 0 to 40 over beats 10...14, with ease in and out.
    private func body(_ t: Double) -> Double {
        let u = min(1, max(0, (t - 10) / 4))
        return 40 * u * u * (3 - 2 * u)
    }

    private func feet(_ t: Double, direction: Int = 1) -> [GremlinFoot] {
        GremlinGait.feet(at: t, walkStart: 10, walkEnd: 14, direction: direction, spread: 5, body: body)
    }

    func testStandsSquareBeforeAndAfterTheWalk() {
        XCTAssertEqual(feet(9), [GremlinFoot(x: -5), GremlinFoot(x: 5)])
        XCTAssertEqual(feet(15), [GremlinFoot(x: 35), GremlinFoot(x: 45)])
    }

    func testOneFootStepsAtATimeOnTheBeat() {
        for step in 0..<4 {
            let mid = feet(10.5 + Double(step))
            let lifted = mid.filter { $0.lift > 0.5 }
            XCTAssertEqual(lifted.count, 1, "one foot in the air at a time")
            // On the beat both feet are down.
            XCTAssertTrue(feet(10 + Double(step) + 1e-9).allSatisfy { $0.lift < 1e-6 })
        }
        // The feet take turns: the trailing (left) foot first when walking right.
        XCTAssertGreaterThan(feet(10.5)[0].lift, 0.5)
        XCTAssertGreaterThan(feet(11.5)[1].lift, 0.5)
        XCTAssertGreaterThan(feet(10.5, direction: -1)[1].lift, 0.5, "walking left, the right foot trails")
    }

    func testPlantedFootNeverSlides() {
        for step in 0..<4 {
            let start = 10 + Double(step)
            let planted = 1 - (step % 2) // the foot not stepping
            let samples = stride(from: start + 0.01, to: start + 0.99, by: 0.07).map { feet($0)[planted].x }
            XCTAssertEqual(samples.max()! - samples.min()!, 0, accuracy: 1e-12)
        }
    }

    func testStepsMoveForward() {
        var last = feet(10)
        for i in 1...10 {
            let now = feet(10 + Double(i) * 0.5)
            XCTAssertGreaterThanOrEqual(now[0].x, last[0].x - 1e-9)
            XCTAssertGreaterThanOrEqual(now[1].x, last[1].x - 1e-9)
            last = now
        }
    }

    func testSwayAlternatesSides() {
        XCTAssertGreaterThan(GremlinGait.sway(at: 10.5, walkStart: 10, walkEnd: 14), 0.9)
        XCTAssertLessThan(GremlinGait.sway(at: 11.5, walkStart: 10, walkEnd: 14), -0.9)
        XCTAssertEqual(GremlinGait.sway(at: 15, walkStart: 10, walkEnd: 14), 0)
    }

    func testNoBigJumpWhileWalking() {
        let lastBeat = GremlinBeat.at(quarter: 3.5, barStart: 0, meter: .common)
        XCTAssertEqual(GremlinPose.dancing(lastBeat).lift, GremlinPose.barJump, accuracy: 1e-9)
        XCTAssertEqual(GremlinPose.dancing(lastBeat, walking: true).lift, GremlinPose.beatHop, accuracy: 1e-9)
    }

    func testWalkIsReportedOnceItStarts() {
        let w = GremlinWander.dancer(2)
        let legStart = Double(3 * w.legBeats) - w.offsetBeats
        let start = legStart + Double(w.restBeats(3))
        XCTAssertNil(w.walk(atBeat: start - 0.5))
        let walk = w.walk(atBeat: start + 0.5)
        XCTAssertEqual(walk?.start, start)
        XCTAssertEqual(walk?.end, start + Double(w.walkBeats(3)))
    }

    // MARK: Blinking

    func testBlinksNowAndThenNotOften() {
        let b = GremlinBlink.dancer(0)
        var blinks = 0
        var wasOpen = true
        var t = 0.0
        while t < 600 {
            let open = b.openness(atSeconds: t) > 0.5
            if wasOpen && !open { blinks += 1 }
            wasOpen = open
            t += 0.01
        }
        // One blink per 6-second window, about a quarter of them double: ~125 in 10 minutes.
        XCTAssertGreaterThan(blinks, 100)
        XCTAssertLessThan(blinks, 150)
    }

    func testABlinkClosesThenOpens() {
        let b = GremlinBlink.dancer(1)
        let at = b.blinkTimes(window: 3)[0]
        XCTAssertEqual(b.openness(atSeconds: at - 0.01), 1)
        XCTAssertEqual(b.openness(atSeconds: at + GremlinBlink.closeSeconds), 0, accuracy: 1e-9)
        XCTAssertEqual(b.openness(atSeconds: at + 0.5), 1, "open again well before the next blink")
    }

    func testDancersBlinkOnTheirOwn() {
        XCTAssertNotEqual(GremlinBlink.dancer(0).blinkTimes(window: 5), GremlinBlink.dancer(1).blinkTimes(window: 5))
    }
}
