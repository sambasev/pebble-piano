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

    static let height: CGFloat = 96

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
        let scale = (size.height * 0.62) / 140
        let bodyWidth = 120 * scale
        let ground = size.height - 2
        let reach = max(0, laneWidth / 2 - bodyWidth / 2 - 4)
        for (i, look) in Self.looks.enumerated() {
            var pose: GremlinPose
            if reduceMotion {
                pose = .rest
            } else if let beat {
                pose = .dancing(beat)
            } else {
                pose = .breathing(seconds: uptime, offset: Double(i) * 1.7)
            }
            if let reaction {
                pose = reaction.apply(to: pose, at: uptime, delay: Double(i) * 0.06)
                if reduceMotion { pose.lift = 0; pose.tilt = 0 }
            }
            let place = reduceMotion ? (x: 0.0, facing: 1) : GremlinWander.dancer(i).position(atBeat: walkTime)
            let centerX = laneWidth * (CGFloat(i) + 0.5) + CGFloat(place.x) * reach
            var c = context
            c.translateBy(x: centerX, y: ground - CGFloat(pose.lift) * 140 * scale)
            c.rotate(by: .radians(pose.tilt))
            let stretch = CGFloat(pose.stretch)
            c.scaleBy(x: CGFloat(place.facing) * scale * (1 - 0.8 * stretch), y: scale * (1 + stretch))
            c.translateBy(x: -60, y: -137)
            Pebble.draw(look, face: pose.face, in: &c)
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

/// The Pebble drawing, in 120 × 140 design units with the feet at the bottom (y ≈ 137).
enum Pebble {
    /// Outlines stay dark in both themes, like the black keys, so the dancers read as
    /// drawings on any background.
    static let ink = Color(hex: 0x1B1630)

    static func draw(_ look: PebbleLook, face: GremlinFace, in c: inout GraphicsContext) {
        let line = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        let outline = StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)

        // Feet.
        c.fill(Path(ellipseIn: CGRect(x: 31, y: 123, width: 26, height: 14)), with: .color(ink))
        c.fill(Path(ellipseIn: CGRect(x: 63, y: 123, width: 26, height: 14)), with: .color(ink))

        // Arms: out to the side, up in a cheer, drooping after a slip.
        var arms = Path()
        switch face {
        case .normal:
            arms.move(to: CGPoint(x: 22, y: 86)); arms.addQuadCurve(to: CGPoint(x: 10, y: 64), control: CGPoint(x: 8, y: 80))
            arms.move(to: CGPoint(x: 98, y: 86)); arms.addQuadCurve(to: CGPoint(x: 110, y: 64), control: CGPoint(x: 112, y: 80))
        case .happy:
            arms.move(to: CGPoint(x: 24, y: 72)); arms.addQuadCurve(to: CGPoint(x: 18, y: 38), control: CGPoint(x: 10, y: 54))
            arms.move(to: CGPoint(x: 96, y: 72)); arms.addQuadCurve(to: CGPoint(x: 102, y: 38), control: CGPoint(x: 110, y: 54))
        case .worried:
            arms.move(to: CGPoint(x: 22, y: 84)); arms.addQuadCurve(to: CGPoint(x: 16, y: 106), control: CGPoint(x: 12, y: 96))
            arms.move(to: CGPoint(x: 98, y: 84)); arms.addQuadCurve(to: CGPoint(x: 104, y: 106), control: CGPoint(x: 108, y: 96))
        }
        c.stroke(arms, with: .color(ink), style: line)

        // Ears.
        var ears = Path()
        switch look.ears {
        case .pair:
            ears.addLines([CGPoint(x: 44, y: 44), CGPoint(x: 48, y: 22), CGPoint(x: 57, y: 41)]); ears.closeSubpath()
            ears.addLines([CGPoint(x: 63, y: 41), CGPoint(x: 72, y: 22), CGPoint(x: 76, y: 44)]); ears.closeSubpath()
        case .single:
            ears.addLines([CGPoint(x: 53, y: 42), CGPoint(x: 60, y: 18), CGPoint(x: 67, y: 42)]); ears.closeSubpath()
        case .wide:
            ears.addLines([CGPoint(x: 40, y: 48), CGPoint(x: 36, y: 26), CGPoint(x: 54, y: 40)]); ears.closeSubpath()
            ears.addLines([CGPoint(x: 66, y: 40), CGPoint(x: 84, y: 26), CGPoint(x: 80, y: 48)]); ears.closeSubpath()
        }
        c.fill(ears, with: .color(look.body))
        c.stroke(ears, with: .color(ink), style: outline)

        // Body and belly.
        let body = Path(ellipseIn: CGRect(x: 18, y: 40, width: 84, height: 88))
        c.fill(body, with: .color(look.body))
        c.stroke(body, with: .color(ink), lineWidth: 4)
        c.fill(Path(ellipseIn: CGRect(x: 36, y: 87, width: 48, height: 30)), with: .color(.white.opacity(0.5)))

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
