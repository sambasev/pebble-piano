#if os(macOS)
import PianoGraderCore
import PianoLessons
import PianoPadState
import SwiftUI
import EarTrainingUI

/// The Learn tab: the unit's pages, a page being played block by block, or a finished page.
struct LearnView: View {
    @ObservedObject var runner: LessonRunner
    @EnvironmentObject var session: PlaySession

    var body: some View {
        Group {
            if let error = runner.loadError {
                VStack(alignment: .leading, spacing: PP.Space.s2) {
                    Text("Couldn't load the lessons").font(.ppHeadline)
                    Text(error).font(.ppCallout).foregroundColor(PP.inkMuted).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .ppGlass()
            } else if let result = runner.result, let page = runner.page {
                PageDoneView(runner: runner, page: page, result: result)
            } else if runner.page != nil {
                PagePlayerView(runner: runner)
            } else if let unit = runner.unit {
                UnitMapView(runner: runner, unit: unit.unit)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Playing a page

private struct PagePlayerView: View {
    @ObservedObject var runner: LessonRunner
    @EnvironmentObject var session: PlaySession
    @Environment(\.ppCompact) private var compact

    /// The bottom part (keyboard, feedback line, controls) has fixed heights and sits at the
    /// bottom of the window; everything that changes size from step to step (stage tabs, the
    /// prompt, the music, results) lives in the flexible area above it. So the keyboard and
    /// buttons stay put however the steps differ. On song pages the keyboard is put away until
    /// mistakes pile up; the music takes its space, and the feedback line and buttons don't move.
    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s3) {
            header
            if let block = runner.shownBlock {
                VStack(alignment: .leading, spacing: PP.Space.s3) {
                    if case .songChallenge = block {
                        if let drill = runner.drill { drillBar(drill) } else { stageBar }
                    }
                    promptCard(block)
                        .tourAnchor(.lessonPrompt)
                    content(block)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                if runner.showsKeyboard {
                    KeyboardView(
                        range: session.displayRange,
                        held: session.held,
                        wrong: session.wrong,
                        expected: session.expected,
                        audition: session.auditionHeld,
                        showGuide: session.showGuide,
                        keyLabel: session.keyLabel(for:),
                        highlight: runner.highlight,
                        onPress: { session.mouseDown(on: $0) },
                        onRelease: { session.mouseUp() }
                    )
                    .frame(height: compact ? PP.Size.keyboardCompact : PP.Size.keyboard)
                    .ppGlass(cornerRadius: PP.Radius.xl, padding: compact ? PP.Space.s2 : PP.Space.s3)
                    .tourAnchor(.keyboard)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if runner.showsDancers, block.kind != .earTraining {
                    DancerStrip(reaction: runner.dancerReaction)
                        .tourAnchor(.dancers)
                }
                feedbackLine
                    .frame(height: Self.feedbackHeight)
                    .tourAnchor(.feedback)
                controls(block)
                    .frame(height: Self.controlsHeight)
                    .tourAnchor(.lessonControls)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: runner.showsKeyboard)
        .onAppear { session.startTourIfNew(.lessonPage) }
    }

    private static let feedbackHeight: CGFloat = 52
    private static let controlsHeight: CGFloat = 56

    /// The music, results or concept card: fills the flexible area.
    @ViewBuilder
    private func content(_ block: Block) -> some View {
        if case .earTraining(let config) = block {
            EarLessonQuizView(session: session.earTraining.session, passAccuracy: config.passAccuracy) { runner.finishEarExercise() }
                .ppGlass(cornerRadius: PP.Radius.lg, padding: 0)
        } else if case .sightReading(let config) = block {
            SightReadingQuizView(session: runner.sightReading, passAccuracy: config.passAccuracy) { runner.finishSightExercise() }
                .ppGlass(cornerRadius: PP.Radius.lg, padding: 0)
        } else if case .songChallenge = block, let result = runner.songResult {
            ScrollView {
                SongResultsCard(runner: runner, result: result)
            }
        } else if block.midi != nil, let score = session.score {
            VStack(alignment: .leading, spacing: PP.Space.s2) {
                if session.showsTempoDisplay { TempoStrip() }
                NotationView(score: score, scoreID: session.scoreID, overlay: overlay(fingering: runner.fingering(for: block) ?? []),
                             tempoProgress: session.showsTempoDisplay
                                 ? { [session] uptime in session.tempoProgress(atUptime: uptime) } : nil,
                             tempoAnimating: session.tempoDisplayMoves)
                    .ppPaper()
                    .tourAnchor(.music)
            }
        } else if case .concept(let card) = block, card.card == "fingerNumbers" {
            FingerNumbersCard()
                .ppGlass(cornerRadius: PP.Radius.lg, padding: PP.Space.s4)
        } else {
            Color.clear
        }
    }

    private var header: some View {
        HStack(spacing: PP.Space.s3) {
            Button {
                runner.backToUnit()
            } label: {
                Label("Lessons", systemImage: "chevron.left")
            }
            .buttonStyle(PPGlassButtonStyle())
            .tourAnchor(.lessonsBack)
            VStack(alignment: .leading, spacing: 2) {
                Text(runner.page?.title ?? "").font(.ppHeadline)
                Text(runner.isWarmingUp ? "Warm-up · about a minute" : "Step \(runner.shownIndex + 1) of \(runner.blockCount)")
                    .font(.ppCaption).foregroundColor(runner.isWarmingUp ? PP.accent : PP.inkMuted)
            }
            Spacer()
            ProgressView(value: Double(runner.shownIndex), total: Double(max(1, runner.blockCount)))
                .frame(width: 200)
                .tint(PP.accent)
        }
    }

    private func promptCard(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            Text(eyebrow(block)).ppEyebrow()
            Text(prompt(block))
                .font(promptFont(block))
                .fixedSize(horizontal: false, vertical: true)
            if let fingering = block.fingering, Set(fingering).count == 1, let finger = fingering.first {
                Text("Finger \(finger)\(finger == 1 ? " (thumb)" : "")")
                    .font(.ppCallout).foregroundColor(PP.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: runner.isChild && block.midi == nil ? 140 : nil, alignment: .leading)
        .ppGlass(cornerRadius: PP.Radius.lg, padding: runner.isChild && block.midi == nil ? PP.Space.s6 : PP.Space.s4)
    }

    /// Explain and concept cards are bigger for children.
    private func promptFont(_ block: Block) -> Font {
        guard block.midi == nil else { return .ppHeadline }
        return runner.isChild ? .system(size: 34, weight: .bold, design: .rounded) : .ppTitle
    }

    private func eyebrow(_ block: Block) -> String {
        switch block {
        case .explain(let b): return b.advanceOn == nil ? "Look" : "Find it"
        case .concept: return "Good to know"
        case .earTraining: return EarCheckWording.eyebrow(newNotes: runner.page?.newNotes ?? [])
        case .sightReading: return "Read it"
        case .wait: return "Your turn: take your time"
        case .listen: return "Listen"
        case .timed: return "Play in time"
        case .songChallenge:
            if let drill = runner.drill, let step = drill.step { return "Fix bar \(drill.measure) · \(step.title)" }
            return runner.songResult != nil ? "Results" : "Song · \(runner.song.current.title)"
        }
    }

    private func prompt(_ block: Block) -> String {
        switch block {
        case .explain(let b): return b.text
        case .concept(let b): return b.text
        case .earTraining(let b): return EarCheckWording.prompt(newNotes: runner.page?.newNotes ?? [], quizNotes: b.notes)
        case .sightReading(let b):
            return SightCurriculum.stage(b.stageID)?.answersAtKeys == true
                ? "Name each note: choose a letter, or play the key." : "Look closely, then choose the answer."
        case .wait(let b): return b.prompt ?? "Play the notes on the staff."
        case .listen(let b): return b.prompt ?? "Listen first."
        case .timed(let b): return b.prompt ?? "Play along with the clicks."
        case .songChallenge(let b):
            let title = runner.songTitle(b)
            if runner.songResult != nil { return title }
            if let drill = runner.drill, let step = drill.step { return drillPrompt(drill, step) }
            switch runner.song.current {
            case .listen: return "\(title). Listen first, and watch the keys light up."
            case .learn: return "Learn \(title) at your own pace: the music waits for each note."
            case .practise: return "Practise with the clicks at \(Int(((b.practiceTempos.first ?? 0.7) * 100).rounded()))% speed. Miss too much and the bar plays again."
            case .perform: return "Perform \(title) at full speed, start to finish. No stops: this run earns your stars."
            }
        }
    }

    @ViewBuilder
    private var feedbackLine: some View {
        HStack(spacing: PP.Space.s3) {
            if let f = runner.feedback {
                PPFeedbackChip(kind: chipKind(f.kind), text: f.text, lines: 2)
                if let stars = f.stars { StarsView(stars: stars) }
            } else if let hintText = runner.hintText {
                PPFeedbackChip(kind: .hint, text: hintText, lines: 2)
            } else if session.isPlayingAlong {
                PPFeedbackChip(kind: .hint, text: session.playAlongState == .countIn ? "Count-in… come in on the next bar." : "Playing: keep going.")
            }
            Spacer()
        }
        .animation(.easeInOut(duration: 0.15), value: runner.feedback)
    }

    private func chipKind(_ kind: LessonRunner.Feedback.Kind) -> PPFeedbackChip.Kind {
        switch kind {
        case .success: return .success
        case .mistake: return .mistake
        case .hint: return .hint
        }
    }

    @ViewBuilder
    private func controls(_ block: Block) -> some View {
        HStack(spacing: PP.Space.s3) {
            switch block {
            case .explain(let b):
                if b.advanceOn == nil {
                    // Nothing to play: Continue counts down for about as long as the card takes to read.
                    TimedContinueButton(title: "Continue",
                                        seconds: AutoAdvance.seconds(.reading(words: AutoAdvance.wordCount(b.text)), child: runner.isChild),
                                        height: PP.Size.targetPrimary) { runner.continueTapped() }
                        .id("explain-\(runner.shownIndex)")
                } else {
                    Text("Play \(b.advanceOn!.name) to continue").font(.ppCallout).foregroundColor(PP.inkMuted)
                }
            case .concept(let b):
                if let check = b.check {
                    Text("Play \(check.name) to continue").font(.ppCallout).foregroundColor(PP.inkMuted)
                } else {
                    // The hand animation takes about 2 s; then time to read.
                    TimedContinueButton(title: "Continue",
                                        seconds: 2 + AutoAdvance.seconds(.reading(words: AutoAdvance.wordCount(b.text)), child: runner.isChild),
                                        height: PP.Size.targetPrimary) { runner.continueTapped() }
                        .id("concept-\(runner.shownIndex)")
                }
            case .earTraining:
                Text("Use the reference and aim for 80% correct.").font(.ppCallout).foregroundColor(PP.inkMuted)
            case .sightReading(let b):
                Text("Aim for \(Int((b.passAccuracy * 100).rounded()))% correct. The examples show every answer.")
                    .font(.ppCallout).foregroundColor(PP.inkMuted)
            case .wait:
                Button(session.isAuditioning ? "Stop" : "Listen") { runner.listen() }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                Button("Restart") { runner.restart() }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
            case .listen:
                Button(session.isAuditioning ? "Stop" : "Listen again") { runner.listen() }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                if runner.listenDone && !session.isAuditioning {
                    TimedContinueButton(title: "Continue", seconds: AutoAdvance.seconds(.stageDone, child: runner.isChild),
                                        height: PP.Size.targetPrimary) { runner.continueTapped() }
                        .id("listen-\(runner.shownIndex)")
                } else {
                    Button("Continue") { runner.continueTapped() }
                        .buttonStyle(PPPrimaryButtonStyle())
                }
            case .timed:
                Button(session.isPlayingAlong ? "Stop" : (session.phase == .graded ? "Try again" : "Start")) {
                    runner.startOrStop()
                }
                .buttonStyle(PPPrimaryButtonStyle())
                Button(session.isAuditioning ? "Stop" : "Listen") { runner.listen() }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                    .disabled(session.isPlayingAlong)
            case .songChallenge:
                if let drill = runner.drill { drillControls(drill) } else if runner.songResult == nil { songControls }
            }
            Spacer()
            if runner.autoHidesKeyboard {
                Button {
                    runner.keyboardPinned.toggle()
                } label: {
                    Label(runner.keyboardPinned ? "Hide keys" : "Show keys", systemImage: "pianokeys")
                }
                .buttonStyle(PPGlassButtonStyle())
                .help("The keyboard comes up by itself after a few mistakes in a row and goes again once you're playing it right. Show keys keeps it up.")
            }
            if runner.canGoBack {
                Button {
                    runner.back()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(PPGlassButtonStyle())
                .help("Go back to step \(runner.shownIndex)")
            }
            if block.midi != nil || block.kind == .explain || block.kind == .concept || block.kind == .earTraining || block.kind == .sightReading {
                Button("Skip") { runner.skip() }
                    .buttonStyle(PPGlassButtonStyle())
                    .help("Move on without finishing this step")
            }
        }
    }

    /// The four song stages as tabs: any can be opened; finished ones get a tick and the
    /// suggested next one is highlighted.
    private var stageBar: some View {
        HStack(spacing: PP.Space.s2) {
            ForEach(SongStage.allCases, id: \.self) { stage in
                let current = runner.song.current == stage && runner.songResult == nil
                let done = runner.song.finished.contains(stage)
                let suggested = runner.song.suggested == stage && !current
                Button {
                    runner.goToStage(stage)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: done ? "checkmark.circle.fill" : "\(stage.rawValue + 1).circle")
                        Text(stage.title)
                    }
                    .font(.ppCallout)
                    .padding(.horizontal, PP.Space.s3).padding(.vertical, 6)
                    .background(Capsule().fill(current ? PP.accent : (suggested ? PP.accent.opacity(0.14) : PP.surfaceRaised.opacity(0.6))))
                    .foregroundColor(current ? PP.onAccent : (done ? PP.success : PP.ink))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(session.isPlayingAlong)
            }
            Spacer()
        }
    }

    private func drillPrompt(_ drill: BarDrill, _ step: DrillStep) -> String {
        let bar = drill.measure
        switch step.kind {
        case .notes: return "Play bar \(bar) at your own pace: the music waits for each note."
        case .slow: return "Bar \(bar) with the clicks at \(Int(step.tempoPercent.rounded()))% speed. It goes round until it's clean."
        case .fullSpeed: return "Bar \(bar) at full speed, round until it's clean."
        case .context: return "Bars \(step.measures.lowerBound)–\(step.measures.upperBound) at full speed: fit bar \(bar) back in."
        }
    }

    /// The drill's steps in place of the stage tabs.
    private func drillBar(_ drill: BarDrill) -> some View {
        HStack(spacing: PP.Space.s2) {
            Label("Fix bar \(drill.measure)", systemImage: "wrench.and.screwdriver")
                .font(.ppCallout)
                .padding(.horizontal, PP.Space.s3).padding(.vertical, 6)
                .background(Capsule().fill(PP.accent))
                .foregroundColor(PP.onAccent)
            ForEach(Array(drill.steps.enumerated()), id: \.offset) { i, step in
                let done = i < drill.stepIndex
                let current = i == drill.stepIndex
                HStack(spacing: 6) {
                    Image(systemName: done ? "checkmark.circle.fill" : "\(i + 1).circle")
                    Text(step.title)
                }
                .font(.ppCallout)
                .padding(.horizontal, PP.Space.s3).padding(.vertical, 6)
                .background(Capsule().fill(current ? PP.accent.opacity(0.14) : PP.surfaceRaised.opacity(0.6)))
                .foregroundColor(done ? PP.success : PP.ink)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func drillControls(_ drill: BarDrill) -> some View {
        if drill.step?.isWaitMode == true {
            Button(session.isAuditioning ? "Stop" : "Listen") { runner.listen() }
                .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
            Button("Restart") { runner.restart() }
                .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
        } else {
            Button(session.isPlayingAlong ? "Stop" : "Start") { runner.startOrStop() }
                .buttonStyle(PPPrimaryButtonStyle())
            Button(session.isAuditioning ? "Stop" : "Listen") { runner.listen() }
                .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                .disabled(session.isPlayingAlong)
            if drill.needed > 1 {
                Text("Clean in a row: \(drill.cleanStreak) of \(drill.needed)")
                    .font(.ppCallout).foregroundColor(PP.inkMuted).monospacedDigit()
            }
        }
        Button("Move on") { runner.drillMoveOn() }
            .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
            .help("Ask \(runner.persona.name) to go to the next step")
        Button("Back to the song") { runner.leaveDrill() }
            .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
    }

    @ViewBuilder
    private var songControls: some View {
        let next = runner.song.current.next
        let finishedHere = runner.song.finished.contains(runner.song.current)
        switch runner.song.current {
        case .listen:
            Button(session.isAuditioning ? "Stop" : "Listen again") { runner.listen() }
                .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
        case .learn:
            Button(session.isAuditioning ? "Stop" : "Listen") { runner.listen() }
                .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
            Button("Restart") { runner.restart() }
                .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
        case .practise, .perform:
            Button(session.isPlayingAlong ? "Stop" : (session.phase == .graded ? "Play again" : "Start")) {
                runner.startOrStop()
            }
            .buttonStyle(PPPrimaryButtonStyle())
            Button(session.isAuditioning ? "Stop" : "Listen") { runner.listen() }
                .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                .disabled(session.isPlayingAlong)
        }
        if let next, !session.isPlayingAlong {
            if finishedHere && runner.autoNextStage == next && !session.isAuditioning {
                TimedContinueButton(title: "Next: \(next.title)", seconds: AutoAdvance.seconds(.stageDone, child: runner.isChild),
                                    height: PP.Size.targetPrimary) { runner.goToStage(next) }
                    .id("stage-\(next.rawValue)")
            } else if finishedHere {
                Button("Next: \(next.title)") { runner.goToStage(next) }
                    .buttonStyle(PPPrimaryButtonStyle())
            } else {
                Button("Skip to \(next.title)") { runner.goToStage(next) }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
            }
        }
    }

    private func overlay(fingering: [Int]) -> ScoreOverlay {
        ScoreOverlay(
            cursorQuarter: session.playheadQuarter,
            auditioning: session.isAuditioning,
            expected: session.showGuide ? session.expected : [],
            played: session.showGuide ? session.playedNotes : [],
            wrong: session.markedWrong,
            mistakeMeasures: session.phase == .graded && session.report != nil ? session.mistakeMeasures : nil,
            fingering: fingering
        )
    }
}

// MARK: - Tempo

/// A slim row above the music: the tempo, a dot per beat lighting on the beat (beat 1 a
/// little bigger) and a thin bar filling across each bar. While the music plays (play-along,
/// count-in included, or Listen) it follows the clicks; otherwise it pulses softly at the
/// target tempo, so the speed is there to feel while learning the notes.
private struct TempoStrip: View {
    @EnvironmentObject var session: PlaySession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Position {
        var beat: Int
        /// 0–1 through the current beat, and through the bar.
        var inBeat: Double
        var inBar: Double
        var live: Bool
        var countIn: Bool
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !session.tempoDisplayMoves)) { _ in
            let p = position(uptime: ProcessInfo.processInfo.systemUptime)
            let beats = max(1, session.meter.numerator)
            HStack(spacing: PP.Space.s3) {
                Text(label(p))
                    .font(.ppCaption).monospacedDigit()
                    .foregroundColor(p.live ? PP.ink : PP.inkMuted)
                    .frame(minWidth: 96, alignment: .leading)
                HStack(spacing: 6) {
                    ForEach(0..<beats, id: \.self) { i in
                        let size: CGFloat = i == 0 ? 11 : 8
                        Circle()
                            .fill(i == p.beat ? PP.accent : PP.inkMuted.opacity(0.3))
                            .frame(width: size, height: size)
                            .opacity(i == p.beat ? flash(p) : 1)
                            .frame(width: 12, height: 12)
                    }
                }
                Spacer()
            }
            .opacity(p.live ? 1 : 0.6)
        }
        .frame(height: 16)
        .padding(.horizontal, PP.Space.s2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tempo \(bpm) beats per minute, \(session.meter.numerator) beats in a bar")
    }

    private var bpm: Int { Int(session.practiceBPM.rounded()) }

    private func label(_ p: Position) -> String {
        if p.countIn { return "Count-in · \(p.beat + 1)" }
        let slowed = session.tempoPercent < 99.5 ? " (\(Int(session.tempoPercent.rounded()))%)" : ""
        return "♩ = \(bpm)\(slowed)"
    }

    /// Bright on the beat, fading through it (steady with Reduce Motion).
    private func flash(_ p: Position) -> Double {
        reduceMotion ? 1 : 1 - 0.65 * p.inBeat
    }

    private func position(uptime: TimeInterval) -> Position {
        let meter = session.meter
        let beatQ = 4.0 / Double(max(1, meter.denominator))
        let barQ = beatQ * Double(max(1, meter.numerator))
        let live = true
        var countIn = false
        let q: Double
        if let now = session.liveQuarter(atUptime: uptime) {
            q = now
            countIn = session.playAlongState == .countIn
        } else if let playing = session.auditionQuarter(atUptime: uptime) {
            q = playing
        } else {
            // Nothing playing: no beat lit.
            return Position(beat: -1, inBeat: 0, inBar: 0, live: false, countIn: false)
        }
        var inBar = (q - session.firstBarQuarter).truncatingRemainder(dividingBy: barQ)
        if inBar < 0 { inBar += barQ }
        let beat = min(max(1, meter.numerator) - 1, Int(inBar / beatQ))
        let inBeat = (inBar - Double(beat) * beatQ) / beatQ
        return Position(beat: beat, inBeat: inBeat, inBar: inBar / barQ, live: live, countIn: countIn)
    }
}

// MARK: - A finished page

private struct PageDoneView: View {
    @ObservedObject var runner: LessonRunner
    let page: LessonPage
    let result: PageResult

    var body: some View {
        VStack(spacing: PP.Space.s4) {
            Spacer()
            Text("Page complete").ppEyebrow()
            Text(page.title).font(.ppTitle)
            if let stars = result.stars {
                StarsView(stars: stars, size: 40)
            }
            if runner.isChild, let sticker = runner.sticker(forPage: page.id) {
                StickerView(sticker: sticker, size: 96)
                Text("You earned the \(sticker.name) sticker!")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            if !page.newNotes.isEmpty {
                Text("You can play " + page.newNotes.map(\.name).joined(separator: ", ") + ".")
                    .font(.ppBody).foregroundColor(PP.inkMuted)
            }
            if !result.flaggedBlocks.isEmpty {
                Text("You skipped \(result.flaggedBlocks.count) step\(result.flaggedBlocks.count == 1 ? "" : "s"): play the page again any time.")
                    .font(.ppCallout).foregroundColor(PP.inkMuted)
            }
            HStack(spacing: PP.Space.s3) {
                Button("Play again") { runner.playAgain() }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetPrimary))
                if let next = runner.nextPageAfterDone {
                    Button("Back to pages") { runner.backToUnit() }
                        .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetPrimary))
                    TimedContinueButton(title: "Next: \(next.title)", seconds: AutoAdvance.seconds(.pageDone, child: runner.isChild),
                                        height: PP.Size.targetPrimary) { runner.openNextPage() }
                        .id("next-\(next.id)")
                } else {
                    Button("Back to pages") { runner.backToUnit() }
                        .buttonStyle(PPPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, PP.Space.s4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ppGlass()
    }
}

/// A right hand, palm down, its fingers numbered 1 (thumb) to 5, resting on C D E F G.
/// The numbers fade in one finger at a time, then stay.
private struct FingerNumbersCard: View {
    @State private var shown = 0
    private let names = ["thumb", "index", "middle", "ring", "little"]
    private let keys = ["C", "D", "E", "F", "G"]
    /// Finger lengths and how far each starts below the knuckle line (the thumb sits low).
    private let lengths: [CGFloat] = [0.42, 0.62, 0.70, 0.64, 0.50]
    private let drops: [CGFloat] = [0.30, 0.04, 0.0, 0.04, 0.12]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let fingerWidth = min(w / 9, h * 0.16)
            let gap = fingerWidth * 0.45
            let total = 5 * fingerWidth + 4 * gap
            let left = (w - total) / 2
            ZStack(alignment: .topLeading) {
                // Palm
                RoundedRectangle(cornerRadius: fingerWidth, style: .continuous)
                    .fill(PP.lilac.opacity(0.55))
                    .frame(width: total + gap, height: h * 0.26)
                    .offset(x: left - gap / 2, y: h * 0.48)
                ForEach(0..<5, id: \.self) { i in
                    let x = left + CGFloat(i) * (fingerWidth + gap)
                    let length = h * lengths[i] * 0.62
                    let top = h * (0.50 + drops[i] * 0.5) - length
                    Capsule()
                        .fill(i < shown ? PP.accent.opacity(0.85) : PP.lilac)
                        .frame(width: fingerWidth, height: length + h * 0.06)
                        .offset(x: x, y: top)
                    // Number above the fingertip
                    Text("\(i + 1)")
                        .font(.system(size: fingerWidth * 0.62, weight: .heavy))
                        .foregroundColor(i < shown ? PP.accent : PP.inkMuted.opacity(0.4))
                        .frame(width: fingerWidth)
                        .offset(x: x, y: top - fingerWidth * 0.95)
                    // Finger name and the key it rests on, below the palm
                    VStack(spacing: 2) {
                        Text(names[i]).font(.ppCaption).foregroundColor(PP.inkMuted)
                        Text(keys[i]).font(.ppHeadline)
                    }
                    .frame(width: fingerWidth + gap)
                    .offset(x: x - gap / 2, y: h * 0.78)
                    .opacity(i < shown ? 1 : 0.35)
                }
            }
        }
        .onAppear {
            shown = 0
            for i in 1...5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 * Double(i)) {
                    withAnimation(.easeOut(duration: 0.25)) { shown = i }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Right hand: thumb 1 on C, index 2 on D, middle 3 on E, ring 4 on F, little 5 on G")
    }
}

/// After a Perform run: stars, notes, timing and help, then what to do next.
private struct SongResultsCard: View {
    @ObservedObject var runner: LessonRunner
    let result: SongResult

    var body: some View {
        HStack(alignment: .center, spacing: PP.Space.s8) {
            VStack(spacing: PP.Space.s2) {
                StarsView(stars: result.stars, size: 36)
                Text(runner.isChild ? Stickers.cheer(stars: result.stars) : headline)
                    .font(runner.isChild ? .system(size: 24, weight: .bold, design: .rounded) : .ppHeadline)
                    .multilineTextAlignment(.center)
            }
            .frame(minWidth: 200)
            VStack(alignment: .leading, spacing: PP.Space.s3) {
                if !runner.isChild {
                    // Children see stars, not percentages.
                    bar("Notes", value: result.summary.notes)
                    if let timing = result.summary.timing { bar("Timing", value: timing) }
                    Label(result.summary.helpUsed ? "Help used: you learned or practised first (up to 2 stars)" : "No help used",
                          systemImage: result.summary.helpUsed ? "hand.raised" : "sparkles")
                        .font(.ppCallout).foregroundColor(PP.inkMuted)
                }
                if !runner.explanations.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(runner.explanations, id: \.self) { line in
                            Label(line, systemImage: "music.note").font(.ppCallout)
                        }
                    }
                }
                if !result.passed {
                    Text(teacherLine)
                        .font(.ppCallout).foregroundColor(PP.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: PP.Space.s3) {
                    if let bar = runner.drillOffer {
                        if runner.drillAutoStart {
                            // The teacher opens the drill herself; hovering pauses, other buttons still work.
                            TimedContinueButton(title: "Fix bar \(bar)", seconds: AutoAdvance.seconds(.drillStarts)) {
                                runner.startDrill()
                            }
                            .id("drill-\(bar)")
                        } else {
                            Button("Fix bar \(bar)") { runner.startDrill() }
                                .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                    Button("Try again") { runner.performAgain() }
                        .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                    Button("Practise") { runner.goToStage(.practise) }
                        .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                    if result.passed {
                        Button("Continue") { runner.continueFromSong() }
                            .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))
                            .keyboardShortcut(.defaultAction)
                    } else if runner.canMoveOnFromSong {
                        Button("Move on anyway") { runner.moveOnFromSong() }
                            .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                            .help("Go to the next page without the stars. The page stays marked to come back to.")
                    }
                }
            }
        }
        .padding(PP.Space.s6)
        .frame(maxWidth: .infinity)
        .ppGlass(cornerRadius: PP.Radius.lg, padding: 0)
    }

    /// The teacher's words when the run didn't earn enough stars.
    private var teacherLine: String {
        let persona = runner.persona
        let need = "\(persona.name) asks for \(result.requiredStars) star\(result.requiredStars == 1 ? "" : "s") to finish the page."
        if let bar = runner.drillOffer {
            return persona.say(.drillOffer, bar: bar) + " " + need
        }
        return persona.say(.performFailed) + " " + need
    }

    private var headline: String {
        switch result.stars {
        case 3: return "Perfect!"
        case 2: return "Great playing!"
        case 1: return "You played it!"
        default: return "Not quite yet"
        }
    }

    private func bar(_ title: String, value: Double) -> some View {
        HStack(spacing: PP.Space.s3) {
            Text(title).font(.ppCallout).frame(width: 60, alignment: .leading)
            ProgressView(value: min(1, max(0, value))).tint(value >= 0.8 ? PP.success : PP.accent).frame(width: 220)
            Text("\(Int((value * 100).rounded()))%").font(.ppCallout).monospacedDigit()
        }
    }
}

/// Filled and empty stars, out of three.
struct StarsView: View {
    let stars: Int
    var size: CGFloat = 16

    var body: some View {
        HStack(spacing: size * 0.2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundColor(i < stars ? PP.warning : PP.inkMuted.opacity(0.5))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stars) of 3 stars")
    }
}
#endif
