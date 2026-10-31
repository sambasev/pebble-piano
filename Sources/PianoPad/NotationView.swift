#if os(macOS)
import PianoGraderCore
import SwiftUI

/// A transcribed score on paper (white, or the night page in dark mode). The engraving is laid out and painted once per width
/// (and again after grading); notes played correctly turn green (repainted when that changes);
/// the playhead, the iris notes the guide waits for and red held wrong keys are drawn over it
/// every frame. The view scrolls to keep the playhead's line in sight.
struct NotationView: View {
    let score: Score
    /// Changes when the score is replaced, so the cached engraving is rebuilt.
    let scoreID: UUID
    let overlay: ScoreOverlay
    /// A measure was clicked (index into the score's measures, from 0).
    var onTapMeasure: ((Int) -> Void)? = nil
    /// The tempo line above the staff (lesson pages): asked every frame. Nil: no line.
    var tempoProgress: ((TimeInterval) -> ScoreProgress?)? = nil
    /// The tempo line is moving (music playing, or the Wait-mode preview).
    var tempoAnimating = true

    @StateObject private var cache = NotationCache()
    @Environment(\.paper) private var paper
    private static let margin: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let width = max(320, Double(geo.size.width - 2 * Self.margin))
            let prepared = cache.prepared(score: score, id: scoreID, width: width, mistakes: overlay.mistakeMeasures,
                                          fingering: overlay.fingering)
            let currentSystem = overlay.cursorQuarter.flatMap { prepared.layout.position(atQuarter: $0)?.system }

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        let played = cache.played(overlay.played, renderer: prepared.renderer)
                        Canvas { context, _ in
                            prepared.painted.paint(paper: paper, in: &context)
                            played.paint(paper: paper, in: &context)
                            DrawingPainter.paint(prepared.renderer.renderLive(overlay), paper: paper, in: &context)
                        }
                        .frame(width: width, height: prepared.layout.height)
                        .overlay(alignment: .topLeading) {
                            PulsingPlayhead(items: prepared.renderer.renderPlayhead(overlay), paper: paper)
                                .frame(width: width, height: prepared.layout.height)
                                .allowsHitTesting(false)
                        }
                        .overlay(alignment: .topLeading) {
                            if let tempoProgress {
                                TempoProgressLine(layout: prepared.layout, paper: paper, progress: tempoProgress,
                                                  animating: tempoAnimating)
                                    .frame(width: width, height: prepared.layout.height)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { point in
                            guard let onTapMeasure,
                                  let m = prepared.layout.measureIndex(atX: point.x, y: point.y) else { return }
                            onTapMeasure(m)
                        }

                        // Invisible rows, one per system, for scrolling to the playhead.
                        VStack(spacing: 0) {
                            ForEach(prepared.layout.systems.indices, id: \.self) { i in
                                Color.clear
                                    .frame(width: 1, height: rowHeight(i, prepared.layout))
                                    .id(i)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .padding(Self.margin)
                }
                .background(paper.page)
                .onChange(of: currentSystem) { system in
                    guard let system else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(system, anchor: .center)
                    }
                }
            }
        }
    }

    /// From the top of one system to the top of the next (the last runs to the bottom).
    private func rowHeight(_ i: Int, _ layout: ScoreLayout) -> CGFloat {
        let systems = layout.systems
        let next = i + 1 < systems.count ? systems[i + 1].top : layout.height
        return max(1, next - systems[i].top)
    }
}

/// Layout and painted engraving for the current score, width and grading state.
final class NotationCache: ObservableObject {
    struct Prepared {
        let layout: ScoreLayout
        let renderer: ScoreRenderer
        let painted: PaintedDrawing
    }

    private var key: (id: UUID, width: Int, mistakes: Set<Int>?, fingering: [Int])?
    private var value: Prepared?
    private var playedKey: (notes: [PlayedNote], width: Int, id: UUID)?
    private var playedValue: PaintedDrawing?

    /// The green layer for the notes played so far, rebuilt only when they change.
    func played(_ notes: [PlayedNote], renderer: ScoreRenderer) -> PaintedDrawing {
        let width = Int(renderer.layout.width.rounded())
        if let playedKey, let playedValue, playedKey.width == width, playedKey.id == key?.id, playedKey.notes == notes {
            return playedValue
        }
        let painted = PaintedDrawing(Drawing(width: renderer.layout.width, height: renderer.layout.height,
                                             items: renderer.renderPlayed(notes)))
        playedKey = (notes, width, key?.id ?? UUID())
        playedValue = painted
        return painted
    }

    func prepared(score: Score, id: UUID, width: Double, mistakes: Set<Int>?, fingering: [Int] = []) -> Prepared {
        let roundedWidth = Int(width.rounded())
        if let key, let value, key.id == id, key.width == roundedWidth, key.mistakes == mistakes, key.fingering == fingering {
            return value
        }
        let layout = ScoreLayout(score: score, width: Double(roundedWidth))
        let renderer = ScoreRenderer(layout: layout)
        let prepared = Prepared(layout: layout, renderer: renderer,
                                painted: PaintedDrawing(renderer.renderScore(mistakeMeasures: mistakes, fingering: fingering)))
        key = (id, roundedWidth, mistakes, fingering)
        value = prepared
        return prepared
    }
}
/// The playhead band, gently pulsing (steady with Reduce Motion). Its own layer, so only the
/// band repaints each frame, not the score.
struct PulsingPlayhead: View {
    let items: [DrawItem]
    let paper: PP.Paper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds per pulse, and the opacity it swings between.
    static let period = 1.2
    static let range: ClosedRange<Double> = 0.45...1

    var body: some View {
        if items.isEmpty {
            Color.clear
        } else if reduceMotion {
            canvas(opacity: 1)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let wave = (sin(2 * .pi * t / Self.period) + 1) / 2
                canvas(opacity: Self.range.lowerBound + (Self.range.upperBound - Self.range.lowerBound) * wave)
            }
        }
    }

    private func canvas(opacity: Double) -> some View {
        Canvas { context, _ in
            context.opacity = opacity
            DrawingPainter.paint(items, paper: paper, in: &context)
        }
    }
}
#endif
