#if os(macOS)
import AppKit
import PianoGraderCore
import SwiftUI

/// Shows a region of a book page (the passage, or the whole page) with overlays:
/// a playhead line, the measure it is in, see-through red circles on the printed staff
/// where held wrong keys sit, and after grading a tint per measure, red where there were mistakes
/// and green where it was clean. Colours come from the `\.paper` palette; in dark mode the printed page is shown
/// inverted onto the night page, lavender ink on dark.
struct ScoreView: View {
    let image: NSImage
    /// The page's media box in PDF points (origin bottom-left).
    let pageBounds: CGRect
    let passage: PassageAnnotation
    let showWholePage: Bool
    let playheadQuarter: Double?
    let graded: Bool
    let mistakeMeasures: Set<Int>
    let auditioning: Bool
    /// Staff lines of each printed measure (measure number → staves, top first).
    var staffPlacements: [Int: [StaffPlacement]] = [:]
    /// Key used to write played notes.
    var noteKey: KeySignature = .cMajor
    /// Wrong notes to draw at the playhead.
    var wrongPitches: Set<Int> = []
    /// Reference notes played correctly: a green circle over each printed note.
    var playedNotes: [PlayedNote] = []
    /// Play-along: the printed measure about to be played again, tinted orange.
    var replayMeasure: Int? = nil
    /// Play-along: the playhead moves with the music every frame, so it isn't animated.
    var followsMusic = false
    /// A printed measure was clicked.
    var onTapMeasure: ((Int) -> Void)? = nil

    @Environment(\.paper) private var paper

    private var region: PageRect {
        if showWholePage {
            return PageRect(x: pageBounds.minX, y: pageBounds.minY, width: pageBounds.width, height: pageBounds.height)
        }
        return passage.box.insetBy(dx: -10, dy: -10)
    }

    var body: some View {
        GeometryReader { geo in
            let region = region
            let scale = max(0.01, min(geo.size.width / region.width, geo.size.height / region.height))
            let location = playheadQuarter.flatMap { passage.location(atQuarter: $0) }

            ZStack(alignment: .topLeading) {
                pageImage
                    .frame(width: pageBounds.width * scale, height: pageBounds.height * scale)
                    .offset(x: (pageBounds.minX - region.x) * scale, y: (region.maxY - pageBounds.maxY) * scale)
                    // The whole page is drawn and clipped to the passage, but clipping doesn't stop
                    // clicks: without this the hidden part of the page sits over the toolbar and
                    // swallows clicks on Wait/Play along, Start and the rest.
                    .allowsHitTesting(false)

                if graded {
                    ForEach(passage.measures, id: \.number) { m in
                        let bad = mistakeMeasures.contains(m.number)
                        Rectangle()
                            .fill(bad ? paper.mistake.opacity(0.16) : paper.success.opacity(0.10))
                            .overlay(alignment: .topLeading) {
                                if bad {
                                    Text("Check bar \(m.number)")
                                        .font(.ppCaption)
                                        .foregroundColor(paper.mistake)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(paper.page.opacity(0.9)))
                                        .padding(4)
                                }
                            }
                            .frame(width: m.box.width * scale, height: m.box.height * scale)
                            .offset(offset(of: m.box, region: region, scale: scale))
                            .allowsHitTesting(false)
                    }
                }

                // Click a measure to play from it.
                if let onTapMeasure {
                    ForEach(passage.measures, id: \.number) { m in
                        Rectangle()
                            .fill(Color.white.opacity(0.001))
                            .frame(width: m.box.width * scale, height: m.box.height * scale)
                            .offset(offset(of: m.box, region: region, scale: scale))
                            .onTapGesture { onTapMeasure(m.number) }
                            .help("Play from bar \(m.number)")
                    }
                }

                // Play-along: the bar with too many misses, about to be played again.
                if let replay = replayMeasure, let m = passage.measure(replay) {
                    Rectangle()
                        .fill(paper.apricot.opacity(0.30))
                        .overlay(alignment: .topLeading) {
                            Text("Again from here")
                                .font(.ppCaption)
                                .foregroundColor(paper.warning)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(paper.page.opacity(0.9)))
                                .padding(4)
                        }
                        .frame(width: m.box.width * scale, height: m.box.height * scale)
                        .offset(offset(of: m.box, region: region, scale: scale))
                        .allowsHitTesting(false)
                }

                // Notes played correctly this time through, green over the printed notes.
                if !playedNotes.isEmpty {
                    Canvas { context, _ in
                        DrawingPainter.paint(playedMarks(region: region, scale: scale), paper: paper, in: &context)
                    }
                    .frame(width: region.width * scale, height: region.height * scale)
                    .allowsHitTesting(false)
                }

                if let location {
                    let box = location.measure.box
                    let tint: Color = auditioning ? paper.audition : paper.accent
                    // The current measure, lightly tinted.
                    Rectangle()
                        .fill(tint.opacity(0.10))
                        .frame(width: box.width * scale, height: box.height * scale)
                        .offset(offset(of: box, region: region, scale: scale))
                        .allowsHitTesting(false)
                    // The playhead: a see-through band reaching a little past the measure, pulsing.
                    let px = (location.x - region.x) * scale
                    let py = (region.maxY - box.maxY) * scale
                    let ph = box.height * scale
                    PulsingLine(color: tint)
                        .frame(width: 16, height: ph + 28)
                        .offset(x: px - 8, y: py - 14)
                        .allowsHitTesting(false)

                    // What was played instead, on the book's own staff.
                    if !wrongPitches.isEmpty, let staves = staffPlacements[location.measure.number], !staves.isEmpty {
                        Canvas { context, _ in
                            DrawingPainter.paint(wrongMarks(staves: staves, x: location.x, region: region, scale: scale), paper: paper, in: &context)
                        }
                        .frame(width: region.width * scale, height: region.height * scale)
                        .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: region.width * scale, height: region.height * scale, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle()) // clicks only inside the visible page region
            .ppPaper()
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .animation(.linear(duration: auditioning || followsMusic ? 0 : 0.12), value: playheadQuarter)
        }
    }

    /// The printed page. In dark mode it's inverted (white paper to black, black ink to white),
    /// tinted with the night page's ink, and screened onto the night page behind it.
    @ViewBuilder
    private var pageImage: some View {
        let base = Image(nsImage: image).resizable().interpolation(.high)
        if paper.isDark {
            ZStack {
                paper.page
                base
                    .colorInvert()
                    .colorMultiply(paper.ink)
                    .blendMode(.screen)
            }
            .compositingGroup()
        } else {
            base
        }
    }

    /// Green circles over the printed notes played correctly. Only the current time through
    /// the music is shown, so after a repeat the marks start again.
    private func playedMarks(region: PageRect, scale: Double) -> [DrawItem] {
        let currentLap = playheadQuarter.flatMap { passage.lap(atQuarter: $0) }
            ?? playedNotes.last.flatMap { passage.lap(atQuarter: $0.quarter) }
        var items: [DrawItem] = []
        for note in playedNotes {
            guard passage.lap(atQuarter: note.quarter) == currentLap,
                  let location = passage.location(atQuarter: note.quarter),
                  let staves = staffPlacements[location.measure.number], !staves.isEmpty else { continue }
            let index = staves.count > 1 ? (note.pitch >= 60 ? 0 : 1) : 0
            let staff = staves[index]
            let clef: Clef = staves.count > 1 ? (index == 0 ? .treble : .bass) : (passage.clef ?? .treble)
            items += PlayedNoteMarks.items(
                pitches: [note.pitch], key: noteKey, clef: clef,
                x: (location.x - region.x) * scale, spacing: staff.spacing * scale,
                color: .playedMark, ledgerLines: false,
                yOfStep: { step in (region.maxY - staff.y(ofStep: step)) * scale })
        }
        return items
    }

    /// See-through circles where the held wrong keys sit on the staff, in the playhead's column.
    /// With two staves in the measure, middle C and above go on the upper (treble) staff.
    private func wrongMarks(staves: [StaffPlacement], x: Double, region: PageRect, scale: Double) -> [DrawItem] {
        let grouped = Dictionary(grouping: wrongPitches) { pitch in staves.count > 1 ? (pitch >= 60 ? 0 : 1) : 0 }
        var items: [DrawItem] = []
        for (index, pitches) in grouped.sorted(by: { $0.key < $1.key }) {
            let staff = staves[index]
            let clef: Clef = staves.count > 1 ? (index == 0 ? .treble : .bass) : (passage.clef ?? .treble)
            let spacing = staff.spacing * scale
            items += PlayedNoteMarks.items(
                pitches: pitches.sorted(), key: noteKey, clef: clef,
                x: (x - region.x) * scale, spacing: spacing,
                yOfStep: { step in (region.maxY - staff.y(ofStep: step)) * scale })
        }
        return items
    }

    /// Top-left of a page rectangle inside the view (y flips: PDF y grows upwards).
    private func offset(of rect: PageRect, region: PageRect, scale: Double) -> CGSize {
        CGSize(width: (rect.x - region.x) * scale, height: (region.maxY - rect.maxY) * scale)
    }
}
/// The book page's playhead band: see-through, gently pulsing (steady with Reduce Motion).
struct PulsingLine: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            line(1)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let wave = (sin(2 * .pi * t / PulsingPlayhead.period) + 1) / 2
                line(PulsingPlayhead.range.lowerBound + (PulsingPlayhead.range.upperBound - PulsingPlayhead.range.lowerBound) * wave)
            }
        }
    }

    private func line(_ opacity: Double) -> some View {
        Capsule()
            .fill(color.opacity(0.24))
            .opacity(opacity)
    }
}
#endif
