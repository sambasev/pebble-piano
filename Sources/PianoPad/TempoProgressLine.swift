#if os(macOS)
import PianoGraderCore
import SwiftUI

/// Where the tempo line is: a point in the music, in quarters from the start, and whether
/// it's the music actually playing (bright) or the target-tempo preview (faint).
struct ScoreProgress {
    var quarter: Double
    var live: Bool
}

/// A thin line across each system of the score, between the finger numbers and the staff,
/// filling from the left as the music goes: in time with the clicks while playing, or sweeping
/// at the target tempo as a preview while learning the notes. Drawn on its own layer every
/// frame, so the engraving underneath isn't repainted.
struct TempoProgressLine: View {
    let layout: ScoreLayout
    let paper: PP.Paper
    /// Asked every frame with the system uptime; nil hides the fill.
    let progress: (TimeInterval) -> ScoreProgress?

    var body: some View {
        TimelineView(.animation) { _ in
            let p = progress(ProcessInfo.processInfo.systemUptime)
            Canvas { context, _ in
                let s = layout.metrics.spacing
                let fillX = p.flatMap { TempoProgressGeometry.position(atQuarter: $0.quarter, in: layout) }
                for system in layout.systems {
                    guard let span = TempoProgressGeometry.span(of: system, spacing: s) else { continue }
                    let y = (system.staffTops.first ?? system.top) - 0.75 * s
                    let thickness = 0.32 * s
                    let track = Path(roundedRect: CGRect(x: span.lowerBound, y: y - thickness / 2,
                                                         width: span.upperBound - span.lowerBound, height: thickness),
                                     cornerRadius: thickness / 2)
                    context.fill(track, with: .color(paper.ink.opacity(0.12)))
                    guard let p, let fillX else { continue }
                    let end: Double
                    if system.index < fillX.system { end = span.upperBound }
                    else if system.index == fillX.system { end = min(span.upperBound, max(span.lowerBound, fillX.x)) }
                    else { continue }
                    guard end > span.lowerBound else { continue }
                    let fill = Path(roundedRect: CGRect(x: span.lowerBound, y: y - thickness / 2,
                                                        width: end - span.lowerBound, height: thickness),
                                    cornerRadius: thickness / 2)
                    context.fill(fill, with: .color(paper.accent.opacity(p.live ? 1 : 0.45)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension PlaySession {
    /// The tempo line in the score: the music while it plays (play-along with or without a
    /// backing track, count-in included, or Listen). In Wait mode, where there's no music to
    /// follow, a faint sweep at the target tempo (through the piece and a bar's rest) gives a
    /// feel for the speed. Otherwise, including once play-along has stopped, the line is empty.
    func tempoProgress(atUptime uptime: TimeInterval) -> ScoreProgress? {
        if let q = liveQuarter(atUptime: uptime) { return ScoreProgress(quarter: q, live: true) }
        if isAuditioning, let q = playheadQuarter { return ScoreProgress(quarter: q, live: true) }
        guard mode == .wait, let score, let last = score.measures.last, phase != .graded else { return nil }
        let start = firstBarQuarter
        let end = Double(last.startSixteenth + last.length) / Double(Score.sixteenthsPerQuarter)
        let bar = 4.0 / Double(max(1, meter.denominator)) * Double(max(1, meter.numerator))
        let cycle = max(0.5, end - start) + bar
        let into = (uptime * max(1, practiceBPM) / 60).truncatingRemainder(dividingBy: cycle)
        return into < end - start ? ScoreProgress(quarter: start + into, live: false) : nil
    }
}

/// The geometry behind the line: pure, so it reads the same as the layout the score was drawn with.
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
