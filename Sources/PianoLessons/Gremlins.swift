import Foundation
import PianoGraderCore

// The Pebbles: three round creatures that dance under the keyboard on a lesson
// page. Everything here is pure (no UI, no clock of its own): the view asks for a pose with
// the music's current position, so the dance can never drift from the clicks.

/// How a time signature is felt by the dancers.
public struct GremlinMeter: Equatable, Sendable {
    /// Beats in a bar: 4 in 4/4, 3 in 3/4, 2 in 6/8.
    public var beatsPerBar: Int
    /// Length of one felt beat in quarter notes: 1 in 4/4, 2 in 2/2, 1.5 in 6/8.
    public var quartersPerBeat: Double

    public init(beatsPerBar: Int, quartersPerBeat: Double) {
        self.beatsPerBar = max(1, beatsPerBar)
        self.quartersPerBeat = max(1e-6, quartersPerBeat)
    }

    /// Compound meters (6/8, 9/8, 12/8, 6/16…) are felt in dotted beats: 6/8 dances as two
    /// beats of a dotted quarter. Everything else counts its denominator: 3/4 is three beats.
    public init(_ ts: TimeSignature) {
        let n = max(1, ts.numerator)
        let unit = 4.0 / Double(max(1, ts.denominator))
        if ts.denominator >= 8, n > 3, n % 3 == 0 {
            self.init(beatsPerBar: n / 3, quartersPerBeat: unit * 3)
        } else {
            self.init(beatsPerBar: n, quartersPerBeat: unit)
        }
    }

    public static let common = GremlinMeter(TimeSignature.common)

    public var quartersPerBar: Double { Double(beatsPerBar) * quartersPerBeat }
}

/// Where the music is, counted the way the dancers count it.
public struct GremlinBeat: Equatable, Sendable {
    /// Bar, counted from the first bar of the music (negative during a count-in).
    public var bar: Int
    /// Beat in the bar, from 0.
    public var beat: Int
    /// How far through the beat, 0..<1.
    public var phase: Double
    public var beatsPerBar: Int

    /// Beats since the first bar line, with the fraction: steady and increasing while the
    /// music plays, so walking can start and stop on whole beats.
    public var beatTime: Double { Double(bar * beatsPerBar + beat) + phase }
    public var isDownbeat: Bool { beat == 0 }
    public var isLastBeat: Bool { beat == beatsPerBar - 1 }

    /// The beat at `quarter`, given the bar it falls in.
    ///
    /// - Parameters:
    ///   - bar: index of the bar that starts at `barStart` (0 for the first bar).
    ///   - barLength: the bar's length in quarters, when it's a short one.
    ///   - pickup: the bar is an upbeat (a short first bar): its beats are the *end* of a
    ///     bar, so the big jump still lands on the first full bar's downbeat.
    ///
    /// Positions outside the bar (a count-in before bar 0, or music past a short last bar)
    /// carry on in whole bars of the meter.
    public static func at(quarter: Double, bar: Int = 0, barStart: Double, barLength: Double? = nil,
                          pickup: Bool = false, meter: GremlinMeter) -> GremlinBeat {
        let full = meter.quartersPerBar
        var offset = quarter - barStart
        if pickup, let length = barLength, length < full { offset += full - length }
        let wraps = (offset / full + 1e-9).rounded(.down)
        offset -= wraps * full
        if offset < 0 { offset = 0 }
        let beats = offset / meter.quartersPerBeat
        var beat = Int((beats + 1e-9).rounded(.down))
        var phase = beats - Double(beat)
        if beat >= meter.beatsPerBar { beat = meter.beatsPerBar - 1; phase = min(phase, 0.999_999) }
        phase = min(max(phase, 0), 0.999_999)
        return GremlinBeat(bar: bar + Int(wraps), beat: beat, phase: phase, beatsPerBar: meter.beatsPerBar)
    }
}

/// How a dancer's body sits in one frame.
public struct GremlinPose: Equatable, Sendable {
    /// Height above the ground, as a fraction of the dancer's height.
    public var lift: Double
    /// Stretch: positive is tall and thin, negative squashed. The view scales height by
    /// 1 + stretch and width by 1 - 0.8 × stretch, anchored at the feet.
    public var stretch: Double
    /// Lean, in radians (positive leans right).
    public var tilt: Double
    public var face: GremlinFace

    public init(lift: Double = 0, stretch: Double = 0, tilt: Double = 0, face: GremlinFace = .normal) {
        self.lift = lift
        self.stretch = stretch
        self.tilt = tilt
        self.face = face
    }

    public static let rest = GremlinPose()

    /// Jump heights, as a fraction of the dancer's height: a small bob on every beat and a big
    /// jump into each new bar.
    public static let beatHop = 0.08
    public static let barJump = 0.28

    /// The dance at `b`: a small bob on each beat; on the last beat of the bar a crouch and a
    /// big jump that lands, squashed, on the next downbeat. In 1/4 every beat is a downbeat.
    ///
    /// While `walking`, every beat is a small bob (each one a step): a big jump mid-stride
    /// looks wrong, and the dancers spend most of their time standing, where it shows.
    public static func dancing(_ b: GremlinBeat, walking: Bool = false) -> GremlinPose {
        let p = b.phase
        let big = b.isLastBeat && !walking
        let height = big ? barJump : beatHop
        let lift = height * 4 * p * (1 - p)
        // Landing squash at the start of each beat: hardest on the downbeat, a crouch before
        // the big jump, light otherwise.
        let landing: Double = walking ? 0.05 : (b.isDownbeat ? 0.16 : (big ? 0.12 : 0.06))
        let squash = -landing * max(0, 1 - p / 0.2)
        let air = p > 0.2 ? (big ? 0.08 : 0.025) * sin(Double.pi * (p - 0.2) / 0.8) : 0
        return GremlinPose(lift: lift, stretch: squash + air)
    }

    /// Standing still with nothing playing: a slow breath.
    public static func breathing(seconds: Double, offset: Double = 0) -> GremlinPose {
        GremlinPose(stretch: 0.02 * sin(2 * Double.pi * seconds / 2.4 + offset))
    }
}

public enum GremlinFace: Equatable, Sendable {
    case normal, happy, worried
}

/// A reaction to the last note: a hop for a right one, a wobble for a wrong one.
public struct GremlinReaction: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case cheer, oops }

    public var kind: Kind
    /// System uptime when the note was played.
    public var startedAt: Double

    public init(kind: Kind, startedAt: Double) {
        self.kind = kind
        self.startedAt = startedAt
    }

    public static let cheerSeconds = 0.45
    public static let oopsSeconds = 0.8
    /// The face stays a moment after the move ends.
    public static let faceHoldSeconds = 0.35

    public var duration: Double { kind == .cheer ? Self.cheerSeconds : Self.oopsSeconds }

    /// What the reaction adds to `base` at `uptime`, `delay` seconds after it starts (so the
    /// three dancers react one after another). After it ends: `base` unchanged.
    public func apply(to base: GremlinPose, at uptime: Double, delay: Double = 0) -> GremlinPose {
        let elapsed = uptime - startedAt - delay
        guard elapsed >= 0, elapsed < duration + Self.faceHoldSeconds else { return base }
        var pose = base
        let t = min(1, elapsed / duration)
        switch kind {
        case .cheer:
            pose.face = .happy
            if elapsed < duration { pose.lift += 0.3 * 4 * t * (1 - t) }
        case .oops:
            pose.face = .worried
            if elapsed < duration { pose.tilt += 0.18 * sin(2 * Double.pi * 2.5 * t) * (1 - t) }
        }
        return pose
    }
}

/// A dancer's stroll around its own lane of the stage, decided by a seed so it looks random
/// but is the same every time for the same beat.
///
/// Time is split into legs of `legBeats` beats. In each leg the dancer walks to a new spot
/// at an unhurried, steady pace (`speed`, the same for every dancer), easing into and out of
/// each step, then stands and dances there for the rest of the leg. Walks start and stop on
/// whole beats, and most of each leg is spent standing, so the movement stays subtle.
public struct GremlinWander: Equatable, Sendable {
    public var seed: UInt64
    /// Beats per leg (walk plus standing).
    public var legBeats: Int
    /// Walking pace in lane widths per beat: from one side of the lane to the other
    /// (-1 to 1) takes 2 / speed beats.
    public var speed: Double
    /// Shifts this dancer's legs so the dancers don't set off together.
    public var offsetBeats: Double

    public static let walkingSpeed = 0.08

    public init(seed: UInt64, legBeats: Int = 32, speed: Double = GremlinWander.walkingSpeed, offsetBeats: Double = 0) {
        self.seed = seed
        self.speed = max(0.01, speed)
        // A leg always has room to cross the whole lane and still stand for a while.
        self.legBeats = max(Int((2 / self.speed).rounded(.up)) + 4, legBeats)
        self.offsetBeats = offsetBeats
    }

    /// The usual three dancers: the same pace, different seeds and starting points.
    public static func dancer(_ index: Int, seed: UInt64 = 0x5EB1E5) -> GremlinWander {
        GremlinWander(seed: seed &+ UInt64(index) &* 0x9E37_79B9, offsetBeats: Double(index) * 11)
    }

    /// Position across the lane at beat time `t`, from -1 (left edge) to 1 (right edge), and
    /// the way the dancer faces: 1 right, -1 left.
    public func position(atBeat t: Double) -> (x: Double, facing: Int) {
        let time = t + offsetBeats
        let length = Double(legBeats)
        let leg = Int((time / length).rounded(.down))
        let local = time - Double(leg) * length
        let rest = Double(restBeats(leg))
        let from = target(leg - 1), to = target(leg)
        let walk = Double(walkBeats(leg))
        if local < rest {
            return (from, facing(leg - 1))
        }
        if local >= rest + walk {
            return (to, facing(leg))
        }
        let u = (local - rest) / walk
        return (from + (to - from) * Self.stride(u, rampFraction: min(0.5, 0.75 / walk)), facing(leg))
    }

    /// The walk in the leg at beat time `t`, once it has started: its first and last beat
    /// (whole beats, in `t`'s time) and its direction. Nil while standing before it.
    public func walk(atBeat t: Double) -> (start: Double, end: Double, direction: Int)? {
        let length = Double(legBeats)
        let leg = Int(((t + offsetBeats) / length).rounded(.down))
        let start = Double(leg) * length - offsetBeats + Double(restBeats(leg))
        guard t >= start else { return nil }
        return (start, start + Double(walkBeats(leg)), facing(leg))
    }

    /// Beats standing at the start of leg `leg` before walking: 2 to 5.
    public func restBeats(_ leg: Int) -> Int {
        min(legBeats - walkBeats(leg), 2 + Int(random(leg, salt: 1) * 4))
    }

    /// Beats walking in leg `leg`: enough to cover the distance at `speed`, at least two.
    public func walkBeats(_ leg: Int) -> Int {
        let distance = abs(target(leg) - target(leg - 1))
        return max(2, Int((distance / speed).rounded(.up)))
    }

    /// Where leg `leg` ends, -1...1.
    func target(_ leg: Int) -> Double { random(leg, salt: 2) * 2 - 1 }

    func facing(_ leg: Int) -> Int { target(leg) >= target(leg - 1) ? 1 : -1 }

    /// Progress 0...1 through a walk at a steady pace, speeding up over the first
    /// `rampFraction` and slowing down over the last: a trapezoidal speed profile.
    static func stride(_ u: Double, rampFraction a: Double) -> Double {
        let u = min(1, max(0, u))
        let top = 1 / (1 - a)
        if u < a { return top * u * u / (2 * a) }
        if u > 1 - a { return 1 - top * (1 - u) * (1 - u) / (2 * a) }
        return top * (u - a / 2)
    }

    /// 0..<1, fixed for a seed, leg and salt.
    private func random(_ leg: Int, salt: UInt64) -> Double {
        let key = Self.mix(UInt64(bitPattern: Int64(leg)) &+ salt &* 0xD1B5_4A32_D192_ED03)
        return Double(Self.mix(seed ^ key) >> 11) / Double(UInt64(1) << 53)
    }

    /// SplitMix64.
    private static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Blinking: each dancer blinks by itself every few seconds, now and then twice in a row.
///
/// Time is cut into windows of `windowSeconds`; in each window the dancer blinks once at a
/// moment picked by the seed (never right at the edges, so blinks don't bunch up), and about
/// one blink in four is a double blink. Same seed and time, same answer.
public struct GremlinBlink: Equatable, Sendable {
    public var seed: UInt64
    public var windowSeconds: Double

    /// How long the lids take to close and to open again.
    public static let closeSeconds = 0.06
    public static let openSeconds = 0.10
    /// The gap between the two blinks of a double blink.
    public static let doubleGapSeconds = 0.28

    public init(seed: UInt64, windowSeconds: Double = 6) {
        self.seed = seed
        self.windowSeconds = max(1, windowSeconds)
    }

    /// The usual three dancers, each on its own schedule.
    public static func dancer(_ index: Int) -> GremlinBlink {
        GremlinBlink(seed: 0xB114C &+ UInt64(index) &* 0x2545_F491_4F6C_DD1D)
    }

    /// How open the eyes are at `seconds`: 1 open, 0 shut.
    public func openness(atSeconds seconds: Double) -> Double {
        let window = Int((seconds / windowSeconds).rounded(.down))
        // A blink late in the previous window may run into this one.
        return min(lids(seconds, window: window), lids(seconds, window: window - 1))
    }

    /// When the blink, or the two of a double blink, in `window` start.
    public func blinkTimes(window: Int) -> [Double] {
        let start = Double(window) * windowSeconds
        let at = start + windowSeconds * (0.1 + 0.8 * random(window, salt: 1))
        return random(window, salt: 2) < 0.25 ? [at, at + Self.doubleGapSeconds] : [at]
    }

    private func lids(_ t: Double, window: Int) -> Double {
        var open = 1.0
        for at in blinkTimes(window: window) {
            let e = t - at
            if e < 0 || e >= Self.closeSeconds + Self.openSeconds { continue }
            let v = e < Self.closeSeconds ? 1 - e / Self.closeSeconds : (e - Self.closeSeconds) / Self.openSeconds
            open = min(open, v)
        }
        return open
    }

    private func random(_ window: Int, salt: UInt64) -> Double {
        let key = gremlinMix(UInt64(bitPattern: Int64(window)) &+ salt &* 0xD1B5_4A32_D192_ED03)
        return Double(gremlinMix(seed ^ key) >> 11) / Double(UInt64(1) << 53)
    }
}

/// SplitMix64, for the dancers' seeded choices.
func gremlinMix(_ x: UInt64) -> UInt64 {
    var z = x &+ 0x9E37_79B9_7F4A_7C15
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
}

/// One foot, in the same units as the body's position: where it is along the floor and how
/// high it's lifted (0 on the ground, 1 at the top of a step).
public struct GremlinFoot: Equatable, Sendable {
    public var x: Double
    public var lift: Double

    public init(x: Double, lift: Double = 0) {
        self.x = x
        self.lift = lift
    }
}

/// Walking with real steps: one step per beat, feet taking turns.
///
/// The foot on the ground stays where it landed while the body moves over it; the other
/// lifts in a small arc and lands half a step ahead of the body, on the beat. The last step
/// of a walk lands at the foot's standing place, and the other foot steps in beside it in the
/// first half beat after, so the dancer ends standing square. Feet never slide.
public enum GremlinGait {
    /// The two feet at time `t` for a walk over `walkStart...walkEnd` (whole beats apart).
    ///
    /// - Parameters:
    ///   - direction: 1 walking right (increasing x), -1 left.
    ///   - spread: how far each foot stands from the body's centre: the left foot's place is
    ///     body - spread, the right foot's body + spread.
    ///   - body: the body's position at any time, in the units wanted back.
    /// - Returns: the left foot, then the right.
    public static func feet(at t: Double, walkStart a: Double, walkEnd b: Double, direction: Int,
                            spread: Double, body x: (Double) -> Double) -> [GremlinFoot] {
        let home = [-spread, spread]
        let steps = max(1, Int((b - a).rounded()))
        guard t >= a else { return home.map { GremlinFoot(x: x(t) + $0) } }
        let d = Double(direction >= 0 ? 1 : -1)
        // Half a step's length: how far ahead of the body a foot lands.
        let lead = abs(x(b) - x(a)) / Double(steps) / 2
        // The trailing foot steps first.
        let trailing = direction >= 0 ? 0 : 1
        func swinging(_ k: Int) -> Int { (trailing + k) % 2 }
        func landing(_ k: Int, _ f: Int) -> Double {
            k == steps - 1 ? x(b) + home[f] : x(a + Double(k + 1)) + home[f] + d * lead
        }
        /// Where foot `f` stands before step `k`: its last landing, or its place at the start.
        func planted(before k: Int, _ f: Int) -> Double {
            var j = k - 1
            while j >= 0 {
                if swinging(j) == f { return landing(j, f) }
                j -= 1
            }
            return x(a) + home[f]
        }
        func arc(_ from: Double, _ to: Double, _ p: Double) -> GremlinFoot {
            let eased = p * p * (3 - 2 * p)
            return GremlinFoot(x: from + (to - from) * eased, lift: sin(Double.pi * p))
        }

        if t < b {
            let k = min(steps - 1, Int((t - a).rounded(.down)))
            let p = t - a - Double(k)
            let f = swinging(k)
            var feet = [GremlinFoot(x: 0), GremlinFoot(x: 0)]
            feet[f] = arc(planted(before: k, f), landing(k, f), p)
            feet[1 - f] = GremlinFoot(x: planted(before: k, 1 - f))
            return feet
        }
        // After the walk: the foot that didn't take the last step steps in beside the other.
        let last = swinging(steps - 1)
        let other = 1 - last
        var feet = [GremlinFoot(x: 0), GremlinFoot(x: 0)]
        feet[last] = GremlinFoot(x: x(b) + home[last])
        let settle = (t - b) / 0.5
        feet[other] = settle < 1 ? arc(planted(before: steps, other), x(b) + home[other], settle)
                                 : GremlinFoot(x: x(b) + home[other])
        return feet
    }

    /// The side-to-side waddle while walking, -1...1: one way on even steps, the other way on
    /// odd ones, 0 standing. Leans the body and swings the arms.
    public static func sway(at t: Double, walkStart a: Double, walkEnd b: Double) -> Double {
        guard t >= a, t < b else { return 0 }
        return sin(Double.pi * (t - a))
    }
}

/// Keeps the stroll going smoothly when the music jumps: a replayed bar, a restart, or
/// stopping and starting again. Walking time only moves forward with the music; after a
/// jump it carries on from where the dancers stood, keeping the beat's fraction so steps
/// still start on a beat.
public struct GremlinWalkClock: Equatable, Sendable {
    public private(set) var time: Double = 0
    private var lastBeat: Double?

    public init() {}

    /// Advances with the music's beat time; nil (nothing playing) holds still.
    public mutating func advance(toBeat beat: Double?) {
        guard let beat else { lastBeat = nil; return }
        defer { lastBeat = beat }
        guard let last = lastBeat else {
            realign(to: beat)
            return
        }
        let delta = beat - last
        if delta >= 0, delta < 1 {
            time += delta
        } else {
            realign(to: beat)
        }
    }

    private mutating func realign(to beat: Double) {
        let fraction = beat - beat.rounded(.down)
        var next = time.rounded(.down) + fraction
        if next < time { next += 1 }
        time = next
    }
}
