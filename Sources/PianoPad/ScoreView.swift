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
    /// Fingered notes from analyzing the transcribed music.
    var fingeringNotes: [FingeredNote] = []
    /// Whether to display finger numbers over the printed sheet music notes.
    var showFingering: Bool = false
    /// Play-along: the printed measure about to be played again, tinted orange.
    var replayMeasure: Int? = nil
    /// Play-along: the playhead moves with the music every frame, so it isn't animated.
    var followsMusic = false
    /// A printed measure was clicked.
    var onTapMeasure: ((Int) -> Void)? = nil
    /// The reference's notes, for finding the printed note under the pointer.
    var referenceNotes: [NoteEvent] = []
    /// The pointer moved onto a printed note (its pitch) or off one (nil).
    var onHoverNote: ((Int?) -> Void)? = nil
    /// A printed note was clicked: its pitch and length in quarters. Not also taken as a click on its measure.
    var onTapNote: ((_ pitch: Int, _ quarters: Double) -> Void)? = nil

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

                // Click a measure to hear it (the click itself is handled below, with notes first).
                if onTapMeasure != nil {
                    ForEach(passage.measures, id: \.number) { m in
                        Rectangle()
                            .fill(Color.white.opacity(0.001))
                            .frame(width: m.box.width * scale, height: m.box.height * scale)
                            .offset(offset(of: m.box, region: region, scale: scale))
                            .help("Click a note to hear it, or the bar to hear bar \(m.number)")
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

                // Automatic Piano Fingering overlay: 1–5 badges above/below printed notes
                if showFingering && !fingeringNotes.isEmpty {
                    ForEach(fingeringBadges(region: region, scale: scale)) { badge in
                        let diameter = max(15, badge.size * 1.35)
                        ZStack {
                            Circle()
                                .fill(paper.page.opacity(0.88))
                                .overlay(Circle().stroke(paper.ink.opacity(0.24), lineWidth: 1))
                            Text("\(badge.finger)")
                                .font(.system(size: max(9, badge.size * 0.85), weight: .bold, design: .rounded))
                                .foregroundColor(paper.ink)
                        }
                        .frame(width: diameter, height: diameter)
                        .offset(x: badge.x - diameter / 2, y: badge.y - diameter / 2)
                        .allowsHitTesting(false)
                    }
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
            .onTapGesture(coordinateSpace: .local) { point in
                if let onTapNote, let hit = note(at: point, region: region, scale: scale) {
                    onTapNote(hit.pitch, hit.quarters)
                    return
                }
                let x = region.x + point.x / scale, y = region.maxY - point.y / scale
                guard let onTapMeasure, let m = passage.measures.first(where: {
                    x >= $0.box.x && x <= $0.box.x + $0.box.width && y >= $0.box.y && y <= $0.box.y + $0.box.height
                }) else { return }
                onTapMeasure(m.number)
            }
            .onContinuousHover { phase in
                guard let onHoverNote else { return }
                switch phase {
                case .active(let point): onHoverNote(note(at: point, region: region, scale: scale)?.pitch)
                case .ended: onHoverNote(nil)
                }
            }
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

    struct FingeringBadge: Identifiable {
        let id: String
        let finger: Int
        let hand: Hand
        let x: Double
        let y: Double
        let size: Double
    }

    private func fingeringBadges(region: PageRect, scale: Double) -> [FingeringBadge] {
        guard showFingering, !fingeringNotes.isEmpty else { return [] }
        var badges: [FingeringBadge] = []
        var seen = Set<String>()

        for note in fingeringNotes {
            guard passage.lap(atQuarter: note.quarter) == 0,
                  let location = passage.location(atQuarter: note.quarter),
                  let staves = staffPlacements[location.measure.number], !staves.isEmpty else { continue }

            let key = "\(location.measure.number)-\(Int(location.x))-\(note.pitch)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            let staffIndex = staves.count > 1 ? (note.hand == .left ? 1 : 0) : 0
            let staff = staves[staffIndex]
            let clef: Clef = staves.count > 1 ? (staffIndex == 0 ? .treble : .bass) : (passage.clef ?? .treble)
            let step = clef.staffStep(of: noteKey.spell(note.pitch))
            let s = staff.spacing * scale

            let noteY = (region.maxY - staff.y(ofStep: step)) * scale
            let staffTopY = (region.maxY - staff.y(ofStep: 8)) * scale
            let staffBottomY = (region.maxY - staff.y(ofStep: 0)) * scale

            let fingerY: Double
            if note.hand == .right || staffIndex == 0 {
                fingerY = min(staffTopY - 1.2 * s, noteY - 1.6 * s)
            } else {
                fingerY = max(staffBottomY + 1.2 * s, noteY + 1.6 * s)
            }
            let fingerX = (location.x - region.x) * scale

            badges.append(FingeringBadge(
                id: "\(note.id)-\(badges.count)",
                finger: note.finger,
                hand: note.hand,
                x: fingerX,
                y: fingerY,
                size: s
            ))
        }
        return badges
    }

    /// The reference note printed under a point of the view, if any. The page only knows where
    /// each bar and staff is, so a note's x is estimated from its beat in the bar; the match is
    /// a little looser across than up and down.
    private func note(at point: CGPoint, region: PageRect, scale: Double) -> (pitch: Int, quarters: Double)? {
        let x = region.x + point.x / scale
        let y = region.maxY - point.y / scale
        var best: (pitch: Int, quarters: Double, distance: Double)?
        for note in referenceNotes {
            guard let location = passage.location(atQuarter: note.onsetBeats),
                  let staves = staffPlacements[location.measure.number], !staves.isEmpty else { continue }
            let box = location.measure.box
            guard x >= box.x, x <= box.x + box.width else { continue }
            let index = staves.count > 1 ? (note.pitch >= 60 ? 0 : 1) : 0
            let staff = staves[index]
            let clef: Clef = staves.count > 1 ? (index == 0 ? .treble : .bass) : (passage.clef ?? .treble)
            let dx = abs(x - location.x), dy = abs(y - staff.y(ofStep: clef.staffStep(of: noteKey.spell(note.pitch))))
            guard dx <= 2.5 * staff.spacing, dy <= 0.75 * staff.spacing else { continue }
            let distance = dy + dx / 4
            let quarters = note.offsetBeats.map { $0 - note.onsetBeats } ?? 1
            if best.map({ distance < $0.distance }) ?? true { best = (note.pitch, quarters, distance) }
        }
        return best.map { ($0.pitch, $0.quarters) }
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
