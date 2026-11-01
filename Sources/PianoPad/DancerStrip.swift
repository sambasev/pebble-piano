#if os(macOS)
import PianoGraderCore
import PianoLessons
import SwiftUI

/// The Pebbles: three round dancers under the keyboard on a child's lesson page.
///
/// While music plays (play-along, count-in or Listen) they dance to it: a small bob on each
/// beat and a big jump that lands on every bar line, in the piece's time signature, strolling
/// about their own patch of the stage between steps. With nothing playing they stand and
/// breathe. A right note in wait mode makes them hop; a slip makes them wobble. Everything
/// is read from the music's own clock each frame, so they can't drift from the clicks.
struct DancerStrip: View {
    @EnvironmentObject var session: PlaySession
    var reaction: GremlinReaction?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Walking time, carried between frames so the stroll survives replays and restarts.
    @State private var memory = Memory()

    static let height: CGFloat = 116

    var body: some View {
        let moving = session.isPlayingAlong || session.isAuditioning
        TimelineView(.animation(minimumInterval: moving ? nil : 1.0 / 20, paused: reduceMotion && reaction == nil)) { _ in
            let uptime = ProcessInfo.processInfo.systemUptime
            let beat = currentBeat(uptime)
            let walk = memory.walk(toBeat: reduceMotion ? nil : beat?.beatTime)
            Canvas { context, size in
                draw(in: &context, size: size, beat: beat, walkTime: walk, uptime: uptime)
            }
        }
        .frame(height: Self.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Timing

    /// The music's position as the dancers count it, or nil when nothing plays.
    private func currentBeat(_ uptime: TimeInterval) -> GremlinBeat? {
        guard let q = session.liveQuarter(atUptime: uptime) ?? session.auditionQuarter(atUptime: uptime) else { return nil }
        let meter = GremlinMeter(session.meter)
        if let bar = session.bar(containing: q) {
            return GremlinBeat.at(quarter: q, bar: bar.index, barStart: bar.start, barLength: bar.length,
                                  pickup: bar.pickup, meter: meter)
        }
        return GremlinBeat.at(quarter: q, barStart: session.firstBarQuarter, meter: meter)
    }

    // MARK: Drawing

    private static let looks: [PebbleLook] = [
        PebbleLook(body: PP.lilac, ears: .pair, eyes: .two),
        PebbleLook(body: PP.apricot, ears: .single, eyes: .one),
        PebbleLook(body: PP.mint, ears: .wide, eyes: .two),
    ]

    private func draw(in context: inout GraphicsContext, size: CGSize, beat: GremlinBeat?, walkTime: Double, uptime: TimeInterval) {
        let count = Self.looks.count
        let laneWidth = size.width / CGFloat(count)
        // The drawing is 120 × 140 design units; leave room above for the big jump.
        let scale = (size.height * 0.68) / 140
        let bodyWidth = 120 * scale
        let ground = size.height - 2
        let reach = max(0, laneWidth / 2 - bodyWidth / 2 - 4)
        for (i, look) in Self.looks.enumerated() {
            let wander = GremlinWander.dancer(i)
            let lane = Double(laneWidth * (CGFloat(i) + 0.5))
            let bodyX: (Double) -> Double = { t in lane + wander.position(atBeat: t).x * Double(reach) }
            let walk = reduceMotion ? nil : wander.walk(atBeat: walkTime)
            let walking = walk.map { walkTime < $0.end } ?? false

            var pose: GremlinPose
            if reduceMotion {
                pose = .rest
            } else if let beat {
                pose = .dancing(beat, walking: walking)
            } else {
                pose = .breathing(seconds: uptime, offset: Double(i) * 1.7)
            }
            // The waddle: a slight lean to each side in turn, arms swinging with it.
            let sway = walk.map { GremlinGait.sway(at: walkTime, walkStart: $0.start, walkEnd: $0.end) } ?? 0
            pose.tilt += 0.05 * sway
            if let reaction {
                pose = reaction.apply(to: pose, at: uptime, delay: Double(i) * 0.06)
                if reduceMotion { pose.lift = 0; pose.tilt = 0 }
            }

            let place = reduceMotion ? (x: 0.0, facing: 1) : wander.position(atBeat: walkTime)
            let centerX = reduceMotion ? lane : bodyX(walkTime)
            // Feet, measured on the floor in points, then into the drawing's units (mirrored
            // with the body when it faces left).
            var feet = Pebble.standingFeet
            if let walk {
                let floor = GremlinGait.feet(at: walkTime, walkStart: walk.start, walkEnd: walk.end, direction: walk.direction,
                                             spread: Double(Pebble.footSpread * scale), body: bodyX)
                feet = floor.map { foot in
                    Pebble.Foot(x: 60 + CGFloat(place.facing) * CGFloat(foot.x - centerX) / scale, lift: CGFloat(foot.lift))
                }
                // Keep each foot on its own hip when the drawing is mirrored.
                if place.facing < 0 { feet.reverse() }
            }

            var c = context
            c.translateBy(x: CGFloat(centerX), y: ground - CGFloat(pose.lift) * 140 * scale)
            c.rotate(by: .radians(pose.tilt))
            let stretch = CGFloat(pose.stretch)
            c.scaleBy(x: CGFloat(place.facing) * scale * (1 - 0.8 * stretch), y: scale * (1 + stretch))
            c.translateBy(x: -60, y: -137)
            Pebble.draw(look, face: pose.face, feet: feet, armSwing: CGFloat(sway), in: &c)
        }
    }

    /// Frame-to-frame state that isn't view state: changing it mustn't redraw anything.
    private final class Memory {
        var clock = GremlinWalkClock()
        func walk(toBeat beat: Double?) -> Double {
            clock.advance(toBeat: beat)
            return clock.time
        }
    }
}

/// One dancer's colours and features.
struct PebbleLook {
    enum Ears { case pair, single, wide }
    enum Eyes { case two, one }
    var body: Color
    var ears: Ears
    var eyes: Eyes
}

/// The Pebble drawing, in 120 × 140 design units with the feet at the bottom (y = 137).
enum Pebble {
    /// Faces (pupils, mouths) stay dark in both themes, inside the coloured body.
    static let ink = Color(hex: 0x1B1630)
    /// Limbs, feet and outlines: a soft grey-lilac that shows on either theme without
    /// standing out (a muted dark grey on a light page, a dim lilac-grey on a dark one).
    static let line = Color.pp(0x4B4566, 0x7A7399)

    /// A foot in the drawing: its centre across (design units) and how far it's lifted, 0...1.
    struct Foot {
        var x: CGFloat
        var lift: CGFloat
    }

    /// How far each foot stands from the body's centre, in design units.
    static let footSpread: CGFloat = 14
    static let standingFeet = [Foot(x: 60 - footSpread, lift: 0), Foot(x: 60 + footSpread, lift: 0)]
    /// How high a stepping foot rises at the top of its arc, in design units.
    static let stepHeight: CGFloat = 9

    /// - Parameters:
    ///   - feet: left, then right (in the drawing's own left and right).
    ///   - armSwing: -1...1 while walking: the arms swing opposite each other.
    static func draw(_ look: PebbleLook, face: GremlinFace, feet: [Foot] = standingFeet, armSwing: CGFloat = 0,
                     in c: inout GraphicsContext) {
        let limb = StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
        let outline = StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)

        // Legs from the hips to the feet, below the body.
        let hips = [CGPoint(x: 50, y: 112), CGPoint(x: 70, y: 112)]
        for (hip, foot) in zip(hips, feet) {
            let ankle = CGPoint(x: foot.x, y: 128 - foot.lift * stepHeight)
            var leg = Path()
            leg.move(to: hip)
            leg.addLine(to: ankle)
            c.stroke(leg, with: .color(line), style: limb)
            c.fill(Path(ellipseIn: CGRect(x: ankle.x - 12, y: ankle.y - 3, width: 24, height: 12)), with: .color(line))
        }

        // Arms reaching out from the sides, with round hands: out to the side, up in a
        // cheer, drooping after a slip.
        let reach: (shoulder: CGPoint, elbow: CGPoint, hand: CGPoint)
        switch face {
        case .normal: reach = (CGPoint(x: 26, y: 84), CGPoint(x: 6, y: 86), CGPoint(x: 6, y: 66))
        case .happy: reach = (CGPoint(x: 28, y: 70), CGPoint(x: 8, y: 58), CGPoint(x: 14, y: 34))
        case .worried: reach = (CGPoint(x: 26, y: 88), CGPoint(x: 8, y: 96), CGPoint(x: 12, y: 112))
        }
        for side in [false, true] {
            let m: (CGPoint) -> CGPoint = { side ? CGPoint(x: 120 - $0.x, y: $0.y) : $0 }
            // Walking: one hand up as the other goes down.
            let swing = CGPoint(x: 0, y: (side ? 1 : -1) * 6 * armSwing)
            let hand = CGPoint(x: m(reach.hand).x, y: m(reach.hand).y + swing.y)
            let elbow = CGPoint(x: m(reach.elbow).x, y: m(reach.elbow).y + swing.y / 2)
            var arm = Path()
            arm.move(to: m(reach.shoulder))
            arm.addQuadCurve(to: hand, control: elbow)
            c.stroke(arm, with: .color(line), style: limb)
            let h = hand
            let palm = Path(ellipseIn: CGRect(x: h.x - 5, y: h.y - 5, width: 10, height: 10))
            c.fill(palm, with: .color(look.body))
            c.stroke(palm, with: .color(line), lineWidth: 3)
        }

        // Horns on top.
        var horns = Path()
        switch look.ears {
        case .pair:
            horns.move(to: CGPoint(x: 40, y: 48))
            horns.addQuadCurve(to: CGPoint(x: 46, y: 14), control: CGPoint(x: 34, y: 26))
            horns.addQuadCurve(to: CGPoint(x: 56, y: 42), control: CGPoint(x: 52, y: 28))
            horns.closeSubpath()
            horns.move(to: CGPoint(x: 80, y: 48))
            horns.addQuadCurve(to: CGPoint(x: 74, y: 14), control: CGPoint(x: 86, y: 26))
            horns.addQuadCurve(to: CGPoint(x: 64, y: 42), control: CGPoint(x: 68, y: 28))
            horns.closeSubpath()
        case .single:
            horns.move(to: CGPoint(x: 50, y: 44))
            horns.addQuadCurve(to: CGPoint(x: 60, y: 8), control: CGPoint(x: 50, y: 22))
            horns.addQuadCurve(to: CGPoint(x: 70, y: 44), control: CGPoint(x: 70, y: 22))
            horns.closeSubpath()
        case .wide:
            horns.move(to: CGPoint(x: 36, y: 54))
            horns.addQuadCurve(to: CGPoint(x: 24, y: 18), control: CGPoint(x: 18, y: 36))
            horns.addQuadCurve(to: CGPoint(x: 52, y: 42), control: CGPoint(x: 40, y: 26))
            horns.closeSubpath()
            horns.move(to: CGPoint(x: 84, y: 54))
            horns.addQuadCurve(to: CGPoint(x: 96, y: 18), control: CGPoint(x: 102, y: 36))
            horns.addQuadCurve(to: CGPoint(x: 68, y: 42), control: CGPoint(x: 80, y: 26))
            horns.closeSubpath()
        }
        c.fill(horns, with: .color(look.body))
        c.stroke(horns, with: .color(line), style: outline)

        // Body and belly.
        let body = Path(ellipseIn: CGRect(x: 22, y: 38, width: 76, height: 80))
        c.fill(body, with: .color(look.body))
        c.stroke(body, with: .color(line), lineWidth: 4)
        c.fill(Path(ellipseIn: CGRect(x: 38, y: 84, width: 44, height: 26)), with: .color(.white.opacity(0.5)))

        drawEyes(look.eyes, face: face, in: &c)
        drawMouth(face, in: &c)
    }

    private static func drawEyes(_ eyes: PebbleLook.Eyes, face: GremlinFace, in c: inout GraphicsContext) {
        let centers: [CGPoint] = eyes == .two ? [CGPoint(x: 46, y: 74), CGPoint(x: 74, y: 74)] : [CGPoint(x: 60, y: 72)]
        let radius: CGFloat = eyes == .two ? 10 : 14
        for (i, center) in centers.enumerated() {
            switch face {
            case .happy:
                // Closed, smiling eyes.
                var arc = Path()
                arc.move(to: CGPoint(x: center.x - 8, y: center.y + 2))
                arc.addQuadCurve(to: CGPoint(x: center.x + 8, y: center.y + 2), control: CGPoint(x: center.x, y: center.y - 8))
                c.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            case .normal, .worried:
                // Worried: one eye a little bigger, both looking up and away.
                let r = face == .worried && i == centers.count - 1 && centers.count > 1 ? radius + 2 : radius
                let eye = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                c.fill(eye, with: .color(.white))
                c.stroke(eye, with: .color(ink), lineWidth: 3)
                let pupilR = r * 0.45
                let look = face == .worried ? CGPoint(x: -2, y: -3) : CGPoint(x: 2, y: 2)
                c.fill(Path(ellipseIn: CGRect(x: center.x + look.x - pupilR, y: center.y + look.y - pupilR,
                                              width: 2 * pupilR, height: 2 * pupilR)), with: .color(ink))
            }
        }
    }

    private static func drawMouth(_ face: GremlinFace, in c: inout GraphicsContext) {
        var mouth = Path()
        switch face {
        case .normal:
            mouth.move(to: CGPoint(x: 50, y: 94))
            mouth.addQuadCurve(to: CGPoint(x: 70, y: 94), control: CGPoint(x: 60, y: 103))
            c.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        case .happy:
            mouth.move(to: CGPoint(x: 46, y: 92))
            mouth.addQuadCurve(to: CGPoint(x: 74, y: 92), control: CGPoint(x: 60, y: 112))
            mouth.closeSubpath()
            c.fill(mouth, with: .color(ink))
        case .worried:
            mouth.move(to: CGPoint(x: 46, y: 98))
            mouth.addQuadCurve(to: CGPoint(x: 54, y: 98), control: CGPoint(x: 50, y: 93))
            mouth.addQuadCurve(to: CGPoint(x: 62, y: 98), control: CGPoint(x: 58, y: 103))
            mouth.addQuadCurve(to: CGPoint(x: 70, y: 98), control: CGPoint(x: 66, y: 93))
            mouth.addQuadCurve(to: CGPoint(x: 74, y: 98), control: CGPoint(x: 72, y: 101))
            c.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }
    }
}
#endif
