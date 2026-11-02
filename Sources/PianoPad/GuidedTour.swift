#if os(macOS)
import PianoLessons
import SwiftUI

/// "Show me around": a short spotlight tour of each screen, presented by a Pebble. Each tour
/// starts by itself the first time a learner reaches its screen, and the ? button in the
/// header (or Help → Show Me Around) plays the one for the screen showing.
enum TourID: String, CaseIterable {
    case practice, learnMap, lessonPage, books, backingTracks, backingEditor
}

/// Something a tour step points at. Views mark themselves with `.tourAnchor(_:)`; a step whose
/// target isn't on screen is left out.
enum TourTarget: Hashable {
    // Shared
    case music, keyboard, dancers, help, inputStatus
    // Practice
    case pieces, mode, listen, gradeReset, report
    // Learn: the unit map
    case unitHeader, continueButton, pageGrid, goalSong
    // Learn: a lesson page
    case lessonsBack, lessonPrompt, feedback, lessonControls
    // Books
    case library, bookMain
    // Backing tracks
    case backingList, backingMain, waveform, transport, markers, timing
}

struct TourStep {
    var target: TourTarget
    var title: String
    var body: String
    /// Shorter, simpler words for a child learner; nil: the same as `body`.
    var childBody: String?

    func text(forChild child: Bool) -> String { child ? childBody ?? body : body }

    /// The keyboard steps invite a try: clicks in the spotlight and note keys reach it.
    var letsYouPlay: Bool { target == .keyboard }
}

extension TourID {
    var steps: [TourStep] {
        switch self {
        case .practice:
            return [
                TourStep(target: .pieces, title: "Choose what to play",
                         body: "Pick a passage from the book or a MIDI file here. ⋯ opens more books and files."),
                TourStep(target: .music, title: "Here are the notes",
                         body: "The music you're playing. The line shows where you are; click a bar to start from there."),
                TourStep(target: .keyboard, title: "Here's the keyboard",
                         body: "The next note lights up. Play it on your piano, click the keys, or use the computer keyboard (A S D F… are the white keys)."),
                TourStep(target: .dancers, title: "Meet the Pebbles",
                         body: "They dance to the beat while the music plays, hop when you get a note right, and wobble when one slips."),
                TourStep(target: .mode, title: "Wait or play along",
                         body: "Wait: the music waits for each note, so take your time. Play along: the music keeps going, and a bar with too many misses is played again."),
                TourStep(target: .listen, title: "Hear it first",
                         body: "Listen plays the piece (Space). Slow it down with the speed next to it."),
                TourStep(target: .gradeReset, title: "Grade or start again",
                         body: "✓ grades your take (Return); ↺ throws it away and starts from the top (Esc)."),
                TourStep(target: .report, title: "How it went",
                         body: "Your grade, the bars to work on and tips from your tutor show up here."),
                TourStep(target: .inputStatus, title: "How you play",
                         body: "A Bluetooth MIDI piano, the microphone or the computer keyboard. Change it here."),
                Self.helpStep,
            ]
        case .learnMap:
            return [
                TourStep(target: .unitHeader, title: "Your lessons",
                         body: "How far you've got, the stars you've earned and your practice streak.",
                         childBody: "See how many pages and stars you have!"),
                TourStep(target: .continueButton, title: "Pick up where you left off",
                         body: "Opens the next page, at the exact step you stopped.",
                         childBody: "Press here to play the next page."),
                TourStep(target: .pageGrid, title: "One page at a time",
                         body: "Pages open in order. Finish one to unlock the next, and play any finished page again for more stars.",
                         childBody: "Finish a page to open the next one."),
                TourStep(target: .goalSong, title: "Your goal song",
                         body: "The song you're working toward. Each page teaches a bit of it.",
                         childBody: "This is your big song. You'll get there!"),
                Self.helpStep,
            ]
        case .lessonPage:
            return [
                TourStep(target: .lessonPrompt, title: "What to do now",
                         body: "Each step tells you what to play or what to look at.",
                         childBody: "This tells you what to do."),
                TourStep(target: .music, title: "Here are the notes",
                         body: "The notes for this step. The line shows where you are.",
                         childBody: "These are the notes to play."),
                TourStep(target: .keyboard, title: "Here's the keyboard",
                         body: "The highlighted key is the next note. Play it on your piano or click it here.",
                         childBody: "Play the key that lights up!"),
                TourStep(target: .dancers, title: "Meet the Pebbles",
                         body: "They dance to the beat, hop when you're right and wobble when a note slips.",
                         childBody: "The Pebbles dance with you. Make them hop!"),
                TourStep(target: .feedback, title: "How each note went",
                         body: "A word after every note, and what to try next.",
                         childBody: "Look here to see how you did."),
                TourStep(target: .lessonControls, title: "Move on",
                         body: "Go to the next step, hear it again or try again.",
                         childBody: "Press here for the next step."),
                TourStep(target: .lessonsBack, title: "Back to your lessons",
                         body: "Your place is saved, so you can stop any time.",
                         childBody: "Go back to all your pages."),
                Self.helpStep,
            ]
        case .books:
            return [
                TourStep(target: .library, title: "Your music books",
                         body: "The books that come with PerfectPiano, books you've opened and pieces you've read from them."),
                TourStep(target: .bookMain, title: "Read a piece",
                         body: "Open a book (a PDF), pick a piece, and PerfectPiano reads the music, checks it with you and teaches it."),
                Self.helpStep,
            ]
        case .backingTracks:
            return [
                TourStep(target: .backingList, title: "Songs to play along with",
                         body: "Your backing tracks. + imports an audio file; only markers and tempo are saved, never the audio."),
                TourStep(target: .backingMain, title: "Set it up once",
                         body: "Mark where bar 1 starts and the tempo, and the track lines up with your piece in Practice."),
                Self.helpStep,
            ]
        case .backingEditor:
            return [
                TourStep(target: .waveform, title: "The song",
                         body: "Drag the markers here, or click to put the cursor where a bar starts."),
                TourStep(target: .transport, title: "Listen and check",
                         body: "Play from the cursor or from bar 1 with the click on. When the click lines up, you're set. The Pebbles dance along."),
                TourStep(target: .markers, title: "Bar 1 and the trim",
                         body: "Stop where a bar starts, then mark it. Trim cuts silence from the start and end."),
                TourStep(target: .timing, title: "Tempo and time",
                         body: "Type the tempo or tap along with the music, and set the time signature and the count-in."),
                Self.helpStep,
            ]
        }
    }

    private static let helpStep = TourStep(
        target: .help, title: "Come back any time",
        body: "Press ? here (or Help → Show Me Around) to see this tour again.",
        childBody: "Press ? to see this again.")
}

// MARK: - Anchors

struct TourAnchorKey: PreferenceKey {
    static var defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks this view as what a tour step points at. Added to what's inside it, so a target
    /// can hold others (the unit map's header holds the Start button).
    func tourAnchor(_ target: TourTarget) -> some View {
        transformAnchorPreference(key: TourAnchorKey.self, value: .bounds) { $0[target] = $1 }
    }
}

// MARK: - The overlay

/// The dimmed window with a hole around the step's target, and the Pebble's card beside it.
/// It covers the whole window, so nothing underneath can be clicked while a tour runs, except
/// the spotlighted keyboard on a step that asks you to try it.
struct TourOverlay: View {
    @EnvironmentObject var session: PlaySession
    let anchors: [TourTarget: Anchor<CGRect>]

    var body: some View {
        if let tour = session.activeTour {
            GeometryReader { geo in
                let bounds = CGRect(origin: .zero, size: geo.size)
                // Only the steps whose target is on screen (at least partly).
                let shown: [(step: TourStep, rect: CGRect)] = tour.steps.compactMap { step in
                    guard let anchor = anchors[step.target] else { return nil }
                    let rect = geo[anchor].intersection(bounds)
                    return rect.isNull || rect.width < 4 || rect.height < 4 ? nil : (step, rect)
                }
                if shown.isEmpty {
                    Color.clear.onAppear { session.endTour() }
                } else {
                    let index = min(session.tourStep, shown.count - 1)
                    let hole = shown[index].rect.insetBy(dx: -8, dy: -8).intersection(bounds.insetBy(dx: 2, dy: 2))
                    ZStack(alignment: .topLeading) {
                        spotlight(hole, in: bounds, open: shown[index].step.letsYouPlay)
                        callout(shown[index].step, number: index + 1, of: shown.count)
                            .frame(width: Self.calloutWidth)
                            .modifier(CalloutPlacement(hole: hole, bounds: bounds, width: Self.calloutWidth))
                    }
                    .animation(.easeInOut(duration: 0.25), value: index)
                    .onAppear {
                        session.tourStepCount = shown.count
                        session.tourLetsYouPlay = shown[index].step.letsYouPlay
                    }
                    .onChange(of: shown.count) { session.tourStepCount = $0 }
                    .onChange(of: shown[index].step.letsYouPlay) { session.tourLetsYouPlay = $0 }
                }
            }
            .transition(.opacity)
        }
    }

    private static let calloutWidth: CGFloat = 380

    private func spotlight(_ hole: CGRect, in bounds: CGRect, open: Bool) -> some View {
        let dim = Path { p in
            p.addRect(bounds)
            p.addRoundedRect(in: hole, cornerSize: CGSize(width: PP.Radius.md, height: PP.Radius.md), style: .continuous)
        }
        return ZStack(alignment: .topLeading) {
            dim.fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            RoundedRectangle(cornerRadius: PP.Radius.md, style: .continuous)
                .strokeBorder(PP.accent, lineWidth: 3)
                .frame(width: hole.width, height: hole.height)
                .offset(x: hole.minX, y: hole.minY)
                .allowsHitTesting(false)
        }
        // Clicks stop here (the tour's buttons move it on), in the hole too unless it's open.
        .contentShape(open ? dim : Path(bounds), eoFill: open)
        .onTapGesture {}
        .accessibilityHidden(true)
    }

    private func callout(_ step: TourStep, number: Int, of count: Int) -> some View {
        let last = number == count
        return HStack(alignment: .top, spacing: PP.Space.s3) {
            PebbleGuide()
                .frame(width: 64, height: 80)
            VStack(alignment: .leading, spacing: PP.Space.s2) {
                Text("\(number) of \(count)").ppEyebrow()
                Text(step.title).font(.ppHeadline)
                Text(step.text(forChild: session.lessonRunner.isChild))
                    .font(.ppCallout)
                    .foregroundColor(PP.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: PP.Space.s2) {
                    if !last {
                        Button("Skip tour") { session.endTour() }
                            .buttonStyle(.borderless)
                            .foregroundColor(PP.inkMuted)
                            .help("Skip the rest (Esc)")
                    }
                    Spacer(minLength: 0)
                    if number > 1 {
                        Button("Back") { session.previousTourStep() }
                            .buttonStyle(PPGlassButtonStyle(height: PP.Size.compact))
                            .help("The step before (←)")
                    }
                    Button(last ? "Done" : "Next") { session.nextTourStep() }
                        .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.compact))
                        .help(last ? "Finish the tour (Return)" : "The next step (Return or →)")
                }
                .padding(.top, PP.Space.s1)
            }
        }
        .foregroundColor(PP.ink)
        .padding(PP.Space.s4)
        .background(RoundedRectangle(cornerRadius: PP.Radius.lg, style: .continuous).fill(PP.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: PP.Radius.lg, style: .continuous).strokeBorder(PP.surfaceGlassEdge, lineWidth: 1))
        .shadow(color: PP.glassShadow, radius: 15, x: 0, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tour, step \(number) of \(count): \(step.title)")
    }
}

/// Puts the card below the target, else above it, centred across it; a tall target gets it
/// beside it, near its top; one as big as the window, inside it. Always kept in the window.
private struct CalloutPlacement: ViewModifier {
    let hole: CGRect
    let bounds: CGRect
    let width: CGFloat

    private static let gap: CGFloat = 12
    private static let margin: CGFloat = 16
    /// About how tall the card is, to choose a side before it's measured.
    private static let roughHeight: CGFloat = 190

    func body(content: Content) -> some View {
        let below = bounds.maxY - hole.maxY - Self.gap - Self.margin >= Self.roughHeight
        let above = hole.minY - Self.gap - Self.margin >= Self.roughHeight
        let side = width + Self.gap + Self.margin
        let right = !below && !above && bounds.maxX - hole.maxX >= side
        let left = !below && !above && !right && hole.minX - bounds.minX >= side
        var x = hole.midX - width / 2
        if right { x = hole.maxX + Self.gap }
        if left { x = hole.minX - Self.gap - width }
        x = min(max(x, Self.margin), bounds.maxX - width - Self.margin)
        return content
            .alignmentGuide(.leading) { _ in -x }
            .alignmentGuide(.top) { d in
                if below { return -(hole.maxY + Self.gap) }
                if above { return d[.bottom] - (hole.minY - Self.gap) }
                // Beside or inside: near the target's top, but never off the bottom.
                return -min(hole.minY + Self.margin, bounds.maxY - d.height - Self.margin)
            }
    }
}

// MARK: - The guide

/// The Pebble who shows the learner around. It dances to the music when something is playing
/// (the same clock as the dancers under the keyboard) and stands and breathes otherwise.
struct PebbleGuide: View {
    @EnvironmentObject var session: PlaySession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let look = PebbleLook(body: PP.lilac, ears: .pair, eyes: .two)

    var body: some View {
        let moving = session.isPlayingAlong || session.isAuditioning
        TimelineView(.animation(minimumInterval: moving ? nil : 1.0 / 20, paused: reduceMotion)) { _ in
            let uptime = ProcessInfo.processInfo.systemUptime
            let beat = reduceMotion ? nil : session.dancerBeat(atUptime: uptime)
            let pose: GremlinPose = reduceMotion ? .rest : beat.map { .dancing($0) } ?? .breathing(seconds: uptime)
            Canvas { context, size in
                // 120 × 140 design units, with headroom for the bar-line jump.
                let scale = min(size.width / 120, size.height / (140 * (1 + GremlinPose.barJump)))
                var c = context
                c.translateBy(x: size.width / 2, y: size.height - 2 - CGFloat(pose.lift) * 140 * scale)
                c.rotate(by: .radians(pose.tilt))
                let stretch = CGFloat(pose.stretch)
                c.scaleBy(x: scale * (1 - 0.8 * stretch), y: scale * (1 + stretch))
                c.translateBy(x: -60, y: -137)
                let blink = GremlinBlink.dancer(0).openness(atSeconds: uptime)
                Pebble.draw(Self.look, face: beat == nil ? .normal : .happy, openness: CGFloat(blink), in: &c)
            }
        }
        .accessibilityHidden(true)
    }
}
#endif
