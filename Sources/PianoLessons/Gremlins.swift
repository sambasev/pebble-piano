import Foundation
import PianoGraderCore

// The Pebbles: three round creatures that dance under the keyboard on a child's lesson
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
    public static func dancing(_ b: GremlinBeat) -> GremlinPose {
        let p = b.phase
        let big = b.isLastBeat
        let height = big ? barJump : beatHop
        let lift = height * 4 * p * (1 - p)
        // Landing squash at the start of each beat: hardest on the downbeat, a crouch before
        // the big jump, light otherwise.
        let landing: Double = b.isDownbeat ? 0.16 : (big ? 0.12 : 0.06)
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
/// but is the same every time for the same beat. Time is split into legs of `legBeats`
/// beats: in each leg the dancer stands for 2–4 whole beats, then walks to a new spot,
/// arriving as the leg ends. So walking always starts and stops on a beat.
public struct GremlinWander: Equatable, Sendable {
    public var seed: UInt64
    /// Beats per leg (rest plus walk), at least 4.
    public var legBeats: Int

    public init(seed: UInt64, legBeats: Int) {
        self.seed = seed
        self.legBeats = max(4, legBeats)
    }

    /// The usual three dancers: different seeds and leg lengths, so they never move in step.
    public static func dancer(_ index: Int, seed: UInt64 = 0x5EB1E5) -> GremlinWander {
        GremlinWander(seed: seed &+ UInt64(index) &* 0x9E37_79B9, legBeats: 6 + index % 3)
    }

    /// Position across the lane at beat time `t`, from -1 (left edge) to 1 (right edge), and
    /// the way the dancer faces: 1 right, -1 left.
    public func position(atBeat t: Double) -> (x: Double, facing: Int) {
        let length = Double(legBeats)
        let leg = Int((t / length).rounded(.down))
        let local = t - Double(leg) * length
        let rest = restBeats(leg)
        let from = target(leg - 1), to = target(leg)
        if local < Double(rest) {
            return (from, facing(leg - 1))
        }
        let u = (local - Double(rest)) / (length - Double(rest))
        let eased = u * u * (3 - 2 * u)
        return (from + (to - from) * eased, facing(leg))
    }

    /// Beats standing still at the start of leg `leg`: 2, 3 or 4, leaving at least two to walk.
    public func restBeats(_ leg: Int) -> Int {
        min(legBeats - 2, 2 + Int(random(leg, salt: 1) * 3))
    }

    /// Where leg `leg` ends, -1...1.
    func target(_ leg: Int) -> Double { random(leg, salt: 2) * 2 - 1 }

    func facing(_ leg: Int) -> Int { target(leg) >= target(leg - 1) ? 1 : -1 }

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
