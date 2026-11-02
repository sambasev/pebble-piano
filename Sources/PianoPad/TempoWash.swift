#if os(macOS)
import PianoGraderCore
import SwiftUI

/// Where the tempo wash has reached: a point in the music, in quarters from the start, and
/// whether it's the music actually playing (stronger) or the target-tempo preview (fainter).
struct ScoreProgress {
    var quarter: Double
    var live: Bool
}

/// A soft iris tint behind the staff lines, filling each system from the left as the music
/// goes. It has no leading line: it fades out at the current point, so nothing lines up with
/// stems, bar lines or ledger lines, and it stays between each staff's outer lines so notes
/// above and below are left clear. Drawn under the engraving on its own layer every frame, so
/// the engraving isn't repainted.
struct TempoWash: View {
    let layout: ScoreLayout
    let paper: PP.Paper
    /// Asked every frame with the system uptime; nil hides the wash.
    let progress: (TimeInterval) -> ScoreProgress?
    /// Redraw every frame only while something moves; otherwise it's drawn once.
    var animating = true

    /// Opacity of the accent at the start of a system and just before the fade.
    static let opacity: ClosedRange<Double> = 0.08...0.18
    /// How far the leading fade runs, in staff spaces.
    static let fadeSpaces = 3.0

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !animating)) { _ in
            let p = progress(ProcessInfo.processInfo.systemUptime)
            Canvas { context, _ in
                guard let p, let fillX = TempoProgressGeometry.position(atQuarter: p.quarter, in: layout) else { return }
                let s = layout.metrics.spacing
                let strength = p.live ? 1 : 0.5
                for system in layout.systems where system.index <= fillX.system {
                    guard let span = TempoProgressGeometry.span(of: system, spacing: s) else { continue }
                    let current = system.index == fillX.system
                    let end = current ? min(span.upperBound, max(span.lowerBound, fillX.x)) : span.upperBound
                    let width = end - span.lowerBound
                    guard width > 0 else { continue }
                    // Earlier systems end at their last barline; the current one fades out.
                    let fade = current ? min(width, Self.fadeSpaces * s) / width : 0
                    let stops: [Gradient.Stop] = [
                        .init(color: paper.accent.opacity(Self.opacity.lowerBound * strength), location: 0),
                        .init(color: paper.accent.opacity(Self.opacity.upperBound * strength), location: 1 - fade),
                        .init(color: paper.accent.opacity(current ? 0 : Self.opacity.upperBound * strength), location: 1),
                    ]
                    let shading = GraphicsContext.Shading.linearGradient(
                        Gradient(stops: stops), startPoint: CGPoint(x: span.lowerBound, y: 0), endPoint: CGPoint(x: end, y: 0))
                    for top in system.staffTops {
                        context.fill(Path(CGRect(x: span.lowerBound, y: top, width: width, height: 4 * s)), with: shading)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension PlaySession {
    /// The tempo wash and beat dots are shown: play-along only (clicks, tempo or a backing
    /// track). Wait mode follows the player, not a beat, so a tempo display would be out of sync.
    var showsTempoDisplay: Bool { mode == .playAlong }

    /// Something on the tempo wash or beat dots is moving (music playing). Otherwise their
    /// frame-by-frame redraw pauses.
    var tempoDisplayMoves: Bool { isPlayingAlong || isAuditioning }


    /// The tempo wash in the score: the music while it plays (play-along with or without a
    /// backing track, count-in included, or Listen). Empty when nothing plays.
    func tempoProgress(atUptime uptime: TimeInterval) -> ScoreProgress? {
        if let q = liveQuarter(atUptime: uptime) { return ScoreProgress(quarter: q, live: true) }
        if let q = auditionQuarter(atUptime: uptime) { return ScoreProgress(quarter: q, live: true) }
        return nil
    }
}

/// The geometry behind the wash: pure, so it reads the same as the layout the score was drawn with.
enum TempoProgressGeometry {
    /// From just before a system's first note to its last barline.
    static func span(of system: ScoreLayout.System, spacing s: Double) -> ClosedRange<Double>? {
        guard let first = system.measures.first, let last = system.measures.last else { return nil }
        let start = (first.columns.values.min() ?? first.x) - 0.8 * s
        return start...max(start + 1, last.maxX)
    }

    /// The x for a point in the music, moving smoothly between note columns (not jumping from
    /// note to note like the playhead). Before the music: nil. After it: the end of the last system.
    static func position(atQuarter quarter: Double, in layout: ScoreLayout) -> (system: Int, x: Double)? {
        let score = layout.score
        guard let lastMeasure = score.measures.last else { return nil }
        let sixteenth = quarter * Double(Score.sixteenthsPerQuarter)
        let firstStart = Double(score.measures.first?.startSixteenth ?? 0)
        guard sixteenth >= firstStart else { return nil }
        if sixteenth >= Double(lastMeasure.startSixteenth + lastMeasure.length) {
            guard let system = layout.systems.last, let ml = system.measures.last else { return nil }
            return (system.index, ml.maxX)
        }
        guard let m = score.measures.firstIndex(where: {
            sixteenth >= Double($0.startSixteenth) && sixteenth < Double($0.startSixteenth + $0.length)
        }) else { return nil }
        let measure = score.measures[m]
        for system in layout.systems {
            guard let ml = system.measures.first(where: { $0.index == m }) else { continue }
            let local = sixteenth - Double(measure.startSixteenth)
            var points = ml.columns.map { (Double($0.key), $0.value) }.sorted { $0.0 < $1.0 }
            if points.first.map({ $0.0 > 0 }) ?? true { points.insert((0, ml.x), at: 0) }
            points.append((Double(measure.length), ml.maxX))
            for i in 0..<(points.count - 1) where local >= points[i].0 && local < points[i + 1].0 {
                let (a, b) = (points[i], points[i + 1])
                let t = (local - a.0) / max(0.0001, b.0 - a.0)
                return (system.index, a.1 + (b.1 - a.1) * t)
            }
            return (system.index, ml.maxX)
        }
        return nil
    }
}
#endif
