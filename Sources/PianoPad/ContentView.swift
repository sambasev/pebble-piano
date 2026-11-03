#if os(macOS)
import AppKit
import PianoGraderCore
import PianoPadState
import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject var session: PlaySession
    @StateObject private var musicLibrary = MusicLibraryModel()
    @State private var showJudgeSettings = false
    @State private var showSettings = false
    @State private var showAISettings = false
    @State private var showTutorChat = false
    @State private var showInput = false
    @State private var progressLearner: Learner?
    @State private var headerWidth: CGFloat = 0
    /// The note under the pointer on the score, ringed on the keyboard.
    @State private var hoveredPitch: Int?
    @AppStorage(PaperStyle.storageKey) private var paperStyle = PaperStyle.matchAppearance
    /// The tutor panel is on Ask (TutorPanel).
    @AppStorage("PianoPad.tutor.asking") private var askingTutor = false
    @Environment(\.ppCompact) private var compact

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, PP.Space.s4)
                .padding(.top, PP.Space.s3)
            switch session.tab {
            case .learn:
                LearnView(runner: session.lessonRunner)
                    .padding(PP.Space.s4)
            case .practice:
                practice
                    .onAppear { session.startTourIfNew(.practice) }
            case .musicLibrary:
                MusicLibraryView(model: musicLibrary)
                    .onAppear { session.startTourIfNew(.musicLibrary) }
            case .books:
                BooksView(model: session.bookImport)
                    .padding(PP.Space.s4)
                    .onAppear { session.startTourIfNew(.books) }
            case .backingTracks:
                BackingTracksView(model: session.backingEditor, store: session.backingStore)
                    .padding(PP.Space.s4)
            }
        }
        .disabled(session.isChoosingLearner)
        .foregroundColor(PP.ink)
        .modifier(SessionSummaryHost(runner: session.lessonRunner))
        .onAppear { session.earTraining.setForeground(NSApp.isActive) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            session.earTraining.setForeground(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            session.earTraining.setForeground(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            session.earTraining.close()
        }
        .overlay {
            // Who's playing: "Add learner" with none yet, "Who's playing?" with several.
            if session.isChoosingLearner {
                LearnerGateView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isChoosingLearner)
        // After setup or "Who's playing?", the screen underneath is new to this learner.
        .onChange(of: session.isChoosingLearner) { choosing in
            if !choosing { session.startTourIfNew(session.currentScreenTour) }
        }
        .alert("Calibrate the microphone?", isPresented: $session.offersCalibration) {
            Button("Calibrate now") { session.startCalibration() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("No Bluetooth MIDI piano is connected, so PerfectPiano listens through the microphone. Play C, D and E on your piano for about 10 seconds so it learns how your piano sounds.")
        }
    }

    /// The app's name, the two sections, and what is listening.
    private var header: some View {
        HStack(spacing: headerWidth < 1100 ? PP.Space.s2 : PP.Space.s4) {
            HStack(spacing: PP.Space.s2) {
                Image(systemName: "pianokeys")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PP.onAccent)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: PP.Radius.sm, style: .continuous).fill(PP.accent))
                    .accessibilityHidden(true)
                Text("PerfectPiano").font(.ppHeadline).lineLimit(1).fixedSize()
            }
            Spacer()
            PPSegmented(selection: $session.tab, [
                (PlaySession.AppTab.learn, "Learn"),
                (PlaySession.AppTab.practice, "Practice"),
                (PlaySession.AppTab.musicLibrary, headerWidth < 1100 ? "Library" : "Music Library"),
                (PlaySession.AppTab.books, "Books"),
                (PlaySession.AppTab.backingTracks, headerWidth < 1100 ? "Tracks" : "Backing tracks")
            ])
            .accessibilityLabel("Section")
            .fixedSize()
            Spacer()
            Button {
                showInput.toggle()
            } label: {
                HStack(spacing: PP.Space.s1) {
                    Image(systemName: session.midiSources.isEmpty && !session.micOn ? "keyboard" : "dot.radiowaves.left.and.right")
                        .foregroundColor(session.midiSources.isEmpty && !session.micOn ? PP.inkMuted : PP.success)
                    Text(session.isEarTrainingActive ? "Listening exercise" : session.inputStatusText)
                        .font(.ppCaption).foregroundColor(PP.ink).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundColor(PP.inkMuted)
                }
                .padding(.horizontal, PP.Space.s2).padding(.vertical, 5)
                .background(Capsule().fill(PP.surfaceRaised.opacity(showInput ? 1 : 0.6)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 280, alignment: .trailing)
            .help("How you play: microphone, Bluetooth MIDI piano or computer keyboard")
            .popover(isPresented: $showInput, arrowEdge: .bottom) {
                InputSettingsView().environmentObject(session).ppDefaultButtons()
            }
            .tourAnchor(.inputStatus)
            if session.canChatWithTutor && session.tab != .practice {
                Button { showTutorChat.toggle() } label: { Image(systemName: "bubble.left.and.bubble.right") }
                    .buttonStyle(PPIconButtonStyle())
                    .accessibilityLabel("Tutor")
                    .help("Chat with your tutor and review practice results")
                    .popover(isPresented: $showTutorChat) {
                        TutorChatView().environmentObject(session)
                            .frame(width: 360, height: 480).padding(PP.Space.s4).ppDefaultButtons()
                    }
            }
            if let learner = session.learner {
                // Narrow windows: just the icon, so the app's name and the input don't get cut.
                Group {
                    if headerWidth >= 1150 {
                        Button { progressLearner = learner } label: {
                            Label("Progress", systemImage: "chart.xyaxis.line")
                        }
                        .buttonStyle(PPGlassButtonStyle())
                        .fixedSize()
                    } else {
                        Button { progressLearner = learner } label: {
                            Image(systemName: "chart.xyaxis.line")
                        }
                        .buttonStyle(PPIconButtonStyle())
                        .accessibilityLabel("Progress")
                    }
                }
                .help("\(learner.name)'s progress: lessons, AI tutor and mistakes over time")
                .sheet(item: $progressLearner) { learner in
                    StudentOverviewView(learner: learner) { progressLearner = nil }
                        .environmentObject(session)
                        .ppDefaultButtons()
                }
            }
            Button {
                session.startTour(session.currentScreenTour)
            } label: {
                Image(systemName: "questionmark")
            }
            .buttonStyle(PPIconButtonStyle(kind: .tool))
            .help("Show me around this screen")
            .accessibilityLabel("Show me around this screen")
            .tourAnchor(.help)
            LearnerMenu()
        }
        .background(GeometryReader { g in
            Color.clear
                .onAppear { headerWidth = g.size.width }
                .onChange(of: g.size.width) { headerWidth = $0 }
        })
    }

    /// The click being handled is the second of a double-click.
    private var isDoubleClick: Bool { (NSApp.currentEvent?.clickCount ?? 1) >= 2 }

    private var practice: some View {
        VStack(alignment: .leading, spacing: compact ? PP.Space.s2 : PP.Space.s3) {
            toolbar
                .ppGlass(cornerRadius: PP.Radius.lg, padding: PP.Space.s3)
            if let engine = session.tutor, !session.tutorPlanning,
               !(compact && askingTutor && session.canChatWithTutor) {
                TutorStepBanner(engine: engine)
            }
            statusLine
                .padding(.horizontal, PP.Space.s2)
            if let passage = session.passage, let image = session.pageImage {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: PP.Space.s3) {
                            Text(passage.instructions ?? passage.title)
                                .font(.ppCallout)
                                .foregroundColor(PP.inkMuted)
                                .lineLimit(2)
                            Spacer()
                            Toggle(isOn: $session.showFingering) {
                                Label("Fingering", systemImage: "hand.point.up.fill")
                            }
                            .toggleStyle(PPChipToggleStyle(height: 28))
                            .help("Show or hide finger numbers on the sheet music notes")
                            PPSegmented(selection: $session.showWholePage, [
                                (false, "Passage"),
                                (true, "Page")
                            ])
                            .accessibilityLabel("View")
                            .fixedSize()
                        }
                        ScoreView(
                            image: image,
                            pageBounds: session.pageBounds,
                            passage: passage,
                            showWholePage: session.showWholePage,
                            playheadQuarter: session.tutorPlayhead,
                            graded: session.phase == .graded && session.report != nil,
                            mistakeMeasures: session.mistakeMeasures.union(session.tutorHighlight),
                            auditioning: session.isAuditioning,
                            staffPlacements: session.staffPlacements,
                            noteKey: session.noteKey,
                            wrongPitches: session.markedWrong,
                            playedNotes: session.showGuide ? session.tutorPlayedNotes : [],
                            fingeringNotes: session.fingeringNotes,
                            showFingering: session.showFingering,
                            replayMeasure: session.replayMeasure,
                            followsMusic: session.isPlayingAlong,
                            // A click chooses where Listen plays from; a double-click plays the bar.
                            onTapMeasure: { session.playFrom(printedMeasure: $0, hear: isDoubleClick) },
                            referenceNotes: session.reference?.notes ?? [],
                            onHoverNote: { hoveredPitch = $0 },
                            onTapNote: { session.auditionNote(pitch: $0, quarters: $1) }
                        )
                        .tourAnchor(.music)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                    reportPanel
                }
            } else if let score = session.score {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(score.title).font(.ppHeadline).lineLimit(1)
                            Text(scoreSummary(score)).font(.ppCallout).foregroundColor(PP.inkMuted).lineLimit(1)
                            Spacer()
                            Toggle(isOn: $session.showFingering) {
                                Label("Fingering", systemImage: "hand.point.up.fill")
                            }
                            .toggleStyle(PPChipToggleStyle(height: 28))
                            .help("Show or hide finger numbers on the sheet music notes")
                        }
                        NotationView(score: score, scoreID: session.scoreID, overlay: notationOverlay,
                                     onTapMeasure: { index in
                                         // Option-click marks the bar to focus on; a click chooses where
                                         // Listen plays from; a double-click plays the bar.
                                         if NSEvent.modifierFlags.contains(.option) { session.toggleMark(bar: index + 1) }
                                         else { session.playFrom(bar: index, hear: isDoubleClick) }
                                     },
                                     // The tempo wash, in play-along only (with or without a backing track).
                                     tempoProgress: session.showsTempoDisplay
                                         ? { [session] uptime in session.tempoProgress(atUptime: uptime) } : nil,
                                     tempoAnimating: session.tempoDisplayMoves,
                                     onHoverNote: { hoveredPitch = $0 },
                                     onTapNote: { session.auditionNote(pitch: $0.midi, quarters: $0.quarters) })
                            .ppPaper()
                            .tourAnchor(.music)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                    reportPanel
                }
            }
            KeyboardView(
                range: session.displayRange,
                held: session.held,
                wrong: session.wrong,
                expected: session.expected,
                audition: session.auditionHeld,
                showGuide: session.showGuide,
                keyLabel: session.keyLabel(for:),
                hovered: hoveredPitch,
                onPress: { session.mouseDown(on: $0) },
                onRelease: { session.mouseUp() }
            )
            .frame(height: compact ? PP.Size.keyboardCompact : PP.Size.keyboard)
            .ppGlass(cornerRadius: PP.Radius.xl, padding: compact ? PP.Space.s2 : PP.Space.s3)
            .tourAnchor(.keyboard)
            // The Pebbles dance to the piece here too, from a book passage or a file.
            if session.showsDancers && (session.passage != nil || session.score != nil) {
                DancerStrip(reaction: session.dancerReaction)
                    .tourAnchor(.dancers)
            }
            playOptions
                .ppGlass(cornerRadius: PP.Radius.lg, padding: PP.Space.s3)
            if session.passage == nil && session.score == nil {
                ReportView(report: session.tutorDisplayReport, phase: session.phase)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .ppGlass()
                    .tourAnchor(.report)
                Spacer(minLength: 0)
            }
        }
        .padding(compact ? PP.Space.s3 : PP.Space.s4)
    }

    /// The grade, or how a take works, on a glass panel beside the music.
    private var reportPanel: some View {
        Group {
            if askingTutor && session.canChatWithTutor {
                // The transcript owns scrolling; the composer stays at the bottom of the panel.
                TutorPanel().environmentObject(session)
            } else {
                ScrollView {
                    VStack(alignment: .leading) {
                        TutorPanel().environmentObject(session)
                        Divider()
                        ReportView(report: session.tutorDisplayReport, phase: session.phase)
                    }
                }
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ppGlass(padding: askingTutor && session.canChatWithTutor && compact ? PP.Space.s3 : PP.Space.s6)
            .frame(width: 340, alignment: .topLeading)
            .tourAnchor(.report)
    }

    /// Passage, listening, grading and rubric.
    private var toolbar: some View {
        HStack(spacing: 12) {
            if session.book != nil || !session.pieces.isEmpty {
                // Book passages and MIDI files in one list.
                PPMenuPicker(title: "Passage", selection: Binding(
                    get: { session.currentPieceTag },
                    // Loading a piece publishes a lot; not while the picker is updating.
                    set: { tag in DispatchQueue.main.async { session.selectPiece(tag) } }
                ), current: currentPieceTitle) {
                    if session.currentPieceTag.isEmpty {
                        Text("Choose a piece").tag("")
                    }
                    if let book = session.book {
                        Section(book.annotations.title) {
                            ForEach(book.annotations.passages) { p in
                                Text(p.title).tag("passage:" + p.id)
                            }
                        }
                    }
                    if !session.pieces.isEmpty {
                        Section("MIDI files") {
                            ForEach(session.pieces, id: \.url) { piece in
                                Text(piece.name).tag("file:" + piece.url.path)
                            }
                        }
                    }
                }
                .frame(minWidth: 160, idealWidth: 260, maxWidth: 280)
                .layoutPriority(-1)
                .help("A book passage, or a MIDI file (⋯ → Open MIDI file… adds more)")
                .tourAnchor(.pieces)
            } else {
                Button {
                    session.chooseReference()
                } label: {
                    Label(session.referenceURL?.lastPathComponent ?? "Open MIDI…", systemImage: "music.note.list")
                        .lineLimit(1)
                }
                .tourAnchor(.pieces)
            }

            PPSegmented(selection: $session.mode, [
                (PlaySession.PracticeMode.wait, "Wait"),
                (PlaySession.PracticeMode.playAlong, "Play along")
            ])
            .accessibilityLabel("Mode")
            .fixedSize()
            .help("Wait: the music waits for each note. Play along: the music keeps going, and a bar with too many misses is played again.")
            .tourAnchor(.mode)

            if session.mode == .playAlong {
                Button {
                    session.togglePlayAlong()
                } label: {
                    Label(session.isPlayingAlong ? "Stop" : "Start",
                          systemImage: session.isPlayingAlong ? "stop.fill" : "play.fill")
                        .frame(width: 60)
                }
                .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.compact))
                .fixedSize()
                .disabled(!session.canPlayAlong)
                .help("Start playing along (Space)")
                .tourAnchor(.listen)
            } else {
                Button {
                    session.toggleAudition()
                } label: {
                    Label(session.isPlayingReference ? "Stop" : "Listen",
                          systemImage: session.isPlayingReference ? "stop.fill" : "play.fill")
                        .frame(width: 60)
                }
                .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.compact))
                .fixedSize()
                .disabled(session.reference == nil || session.phase == .recording)
                .help(session.listenFromBar.map { "Hear the reference from bar \($0 + 1) (Space). Click a bar to choose where; double-click to hear just that bar" }
                      ?? "Hear the reference (Space). Click a bar to listen from there; double-click to hear just that bar")
                .tourAnchor(.listen)
            }

            if session.mode == .playAlong {
                tempoControl
            } else {
                PPMenuPicker(title: "Speed", selection: $session.auditionSpeed,
                             current: "\(Int((session.auditionSpeed * 100).rounded()))%") {
                    Text("50%").tag(0.5)
                    Text("75%").tag(0.75)
                    Text("100%").tag(1.0)
                }
                .frame(width: 100)
                .help("Listening speed")
            }

            HStack(spacing: 12) {
                Button { session.finishTake() } label: { Image(systemName: "checkmark") }
                    .buttonStyle(PPIconButtonStyle(kind: .tool))
                    .disabled(!session.canFinishTake)
                    .help("Finish the take and grade it (Return)")
                    .accessibilityLabel("Grade the take")

                Button { session.resetAll() } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(PPIconButtonStyle(kind: .tool))
                    .disabled(!session.canReset)
                    .help("Stop, discard the take and start again from the beginning (Esc)")
                    .accessibilityLabel("Start again")
            }
            .tourAnchor(.gradeReset)

            Spacer(minLength: PP.Space.s2)

            Button { showSettings.toggle() } label: {
                Image(systemName: "slider.horizontal.3")
                    .overlay(alignment: .topTrailing) {
                        if needsBackingTrack {
                            Circle().fill(PP.warning).frame(width: 7, height: 7).offset(x: 7, y: -7)
                        }
                    }
            }
            .buttonStyle(PPIconButtonStyle(kind: .tool, isOn: showSettings))
            .help(needsBackingTrack ? "Practice settings: this piece has no backing track linked"
                                    : "Practice settings: backing track, metronome, judge and rubric")
            .accessibilityLabel("Practice settings")
            .popover(isPresented: $showSettings, arrowEdge: .bottom) { practiceSettings.ppDefaultButtons() }

            Menu {
                Button("Open book…") { session.chooseBook() }
                Button("Open MIDI file…") { session.chooseReference() }
                Button("Open rubric file…") { session.chooseRubric() }
                Divider()
                Button("Export MusicXML…") { session.exportMusicXML() }.disabled(!session.canExportMusicXML)
                Button("Save take…") { session.saveTake() }.disabled(!session.canSaveTake)
                Button("Connect a Bluetooth MIDI piano…") { session.showBluetoothMIDIPairing() }
                Button("Rescan Bluetooth MIDI") { session.startMIDI() }
                Divider()
                Button("Calibrate piano (mic)…") { session.startCalibration() }
                Button("Measure silence (mic noise gate)") { session.measureSilence() }
                Button("Clear piano calibration") { session.clearCalibration() }.disabled(!session.isCalibrated)
                Divider()
                Button("AI settings…") { showAISettings = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(PP.ink)
            }
            .menuStyle(.button)
            .buttonStyle(PPIconButtonStyle(kind: .tool))
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Open, export, MIDI devices, microphone calibration and AI settings")
            .sheet(isPresented: $showAISettings) { AISettingsView { showAISettings = false }.ppDefaultButtons() }
        }
    }

    /// The noise gate: its level, a ± adjustment, and a hint to measure the room.
    private var gateControl: some View {
        HStack(spacing: 2) {
            if let db = session.gateDB {
                Text("Gate \(Int(db.rounded())) dB")
                    .font(.ppCaption.monospacedDigit())
                    .foregroundColor(PP.inkMuted)
                PPStepper(value: $session.gateOffsetDB, in: -12...12, step: 3)
            } else {
                Button("Measure silence") { session.measureSilence() }
                    .controlSize(.small)
            }
        }
        .help(session.gateDB == nil
              ? "No noise gate measured yet: the mic measures the room for a moment when it starts. Measure silence (or calibrate) to set one."
              : "Noise gate (dBFS): notes start only above it. \(session.gateOffsetDB == 0 ? "As measured" : String(format: "%+.0f dB from the measured value", session.gateOffsetDB)). Raise it if noise sets off notes; lower it if soft notes are missed.")
    }

    /// The practice tempo in the toolbar: presets, ±5% steps and the resulting bpm.
    private var tempoControl: some View {
        HStack(spacing: PP.Space.s1) {
            tempoPicker
            PPStepper(value: $session.tempoPercent, in: PlaySession.tempoRange, step: 5)
            if session.originalBPM != nil {
                Text("\(Self.bpm((session.practiceBPM * 10).rounded() / 10)) bpm")
                    .font(.ppCaption)
                    .monospacedDigit()
                    .foregroundColor(tempoInk)
                    .fixedSize()
            }
        }
        .help("Practice tempo. Changing it while playing restarts the current bar. Type an exact bpm in Practice settings.")
    }

    private var tempoPicker: some View {
        PPMenuPicker(title: "Practice tempo", selection: $session.tempoPercent,
                     current: "\(Int(session.tempoPercent))%") {
            ForEach(PlaySession.tempoPresets, id: \.self) { p in
                Text(p == 100 ? "100% (original)" : "\(Int(p))%").tag(p)
            }
            if !PlaySession.tempoPresets.contains(session.tempoPercent) {
                Text("\(Int(session.tempoPercent))%").tag(session.tempoPercent)
            }
        }
        .frame(width: 104)
    }

    /// The Passage picker's label: the open book passage or MIDI file.
    private var currentPieceTitle: String {
        let tag = session.currentPieceTag
        if tag.hasPrefix("passage:"), let p = session.book?.annotations.passages.first(where: { "passage:" + $0.id == tag }) {
            return p.title
        }
        if tag.hasPrefix("file:"), let piece = session.pieces.first(where: { "file:" + $0.url.path == tag }) {
            return piece.name
        }
        return "Choose a piece"
    }

    private var rubricTitle: String {
        switch session.rubricChoice {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .file: return session.rubricFileName ?? "Rubric file"
        }
    }

    private var tempoInk: Color {
        session.tempoPercent < 100 ? PP.accent : session.tempoPercent > 100 ? PP.warning : PP.ink
    }

    /// The piece's own tempo, and an exact practice bpm.
    private var tempoDetail: some View {
        HStack(spacing: PP.Space.s2) {
            if let original = session.originalBPM {
                Text("♩ = \(Self.bpm(original))")
                    .monospacedDigit()
                    .foregroundColor(PP.inkMuted)
                    .help(session.linkedTrackID != nil
                          ? "The piece's tempo, from the linked backing track" + (session.fileBPM.map { " (the MIDI file says \(Self.bpm($0)))" } ?? "")
                          : "The piece's tempo, from the MIDI file")
                Text("→").foregroundColor(PP.inkMuted)
            }
            TextField("bpm", value: Binding(get: { (session.practiceBPM * 10).rounded() / 10 },
                                            set: { session.practiceBPM = $0 }),
                      format: .number.precision(.fractionLength(0...1)))
                .ppField()
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .foregroundColor(tempoInk)
                .disabled(session.originalBPM == nil)
            Text("bpm").foregroundColor(PP.inkMuted)
        }
    }

    private var needsBackingTrack: Bool {
        session.mode == .playAlong && session.reference != nil && !session.hasBackingTrack
    }

    /// Set-once options, kept out of the toolbar so the lesson controls fit any window.
    private var practiceSettings: some View {
        VStack(alignment: .leading, spacing: PP.Space.s4) {
            Text("Audio").ppEyebrow()
            AudioDevicesView()
            if session.mode == .playAlong {
                Text("Play along").ppEyebrow()
                Grid(alignment: .leading, horizontalSpacing: PP.Space.s4, verticalSpacing: PP.Space.s3) {
                    GridRow {
                        Text("Backing track")
                        backingMenu
                    }
                    GridRow {
                        Text("Tempo")
                        tempoDetail
                    }
                    GridRow {
                        Text("Metronome")
                        Toggle("Click on every beat", isOn: $session.metronomeOn)
                            .toggleStyle(PPChipToggleStyle())
                            .help("From the next start or replay")
                    }
                    GridRow {
                        Text("On a miss")
                        PPMenuPicker(title: "On a miss", selection: $session.missMode, current: session.missMode.title) {
                            ForEach(PlaySession.MissMode.allCases) { Text($0.title).tag($0) }
                        }
                        .frame(width: 240)
                        .help("Replay the bar from the bar before, or stop and wait until you play the note. Takes effect at the next miss.")
                    }
                    GridRow {
                        Text("Judge")
                        PPMenuPicker(title: "Judge", selection: $session.strictness, current: session.strictness.title) {
                            ForEach(PlaySession.Strictness.allCases) { Text($0.title).tag($0) }
                        }
                        .frame(width: 240)
                        .help("How forgiving play-along is. Changes apply straight away, even mid-bar.")
                    }
                }
                DisclosureGroup("Fine-tune the judge", isExpanded: $showJudgeSettings) {
                    JudgeSettingsView(session: session)
                }
                Divider()
            }
            Text("Display").ppEyebrow()
            Grid(alignment: .leading, horizontalSpacing: PP.Space.s4, verticalSpacing: PP.Space.s3) {
                GridRow {
                    Text("Sheet music")
                    PPSegmented(selection: $paperStyle, PaperStyle.allCases.map { ($0, $0.title) })
                    .accessibilityLabel("Sheet music")
                    .fixedSize()
                    .help("Dark shows the music as light ink on a dim page, easier on the eyes at night. Match appearance follows the Mac's light or dark mode.")
                }
            }
            Divider()
            Text("Grading").ppEyebrow()
            Grid(alignment: .leading, horizontalSpacing: PP.Space.s4, verticalSpacing: PP.Space.s3) {
                GridRow {
                    Text("Rubric")
                    PPMenuPicker(title: "Rubric", selection: $session.rubricChoice, current: rubricTitle) {
                        Text("Beginner").tag(PlaySession.RubricChoice.beginner)
                        Text("Intermediate").tag(PlaySession.RubricChoice.intermediate)
                        if let name = session.rubricFileName {
                            Text(name).tag(PlaySession.RubricChoice.file)
                        }
                    }
                    .frame(width: 240)
                }
                GridRow {
                    Text("Auto-grade")
                    Toggle("Grade when the passage ends", isOn: $session.autoGrade)
                        .toggleStyle(PPChipToggleStyle())
                        .help("Grade automatically \(String(format: "%g", PlaySession.autoGradeDelay)) s after the last note of the passage")
                }
            }
        }
        .font(.ppCallout)
        .foregroundColor(PP.ink)
        .tint(PP.accent)
        .padding(PP.Space.s6)
        .frame(width: 500)
    }

    private static func bpm(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    /// Which saved backing track the open passage or MIDI file plays along with.
    private var backingMenu: some View {
        let store = session.backingStore
        return Menu {
            Button {
                session.linkBackingTrack(nil)
            } label: {
                if session.linkedTrackID == nil { Label("Not linked", systemImage: "checkmark") } else { Text("Not linked") }
            }
            if !store.tracks.isEmpty { Divider() }
            ForEach(store.tracks) { track in
                Button {
                    session.linkBackingTrack(track.id)
                } label: {
                    let title = String(format: "%@ · %.0f bpm · %d/%d", track.name, track.bpm,
                                       track.timeSignature.numerator, track.timeSignature.denominator)
                    if session.linkedTrackID == track.id { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
            Divider()
            Button("Edit backing tracks…") { session.tab = .backingTracks }
        } label: {
            Label(session.backingName ?? "Missing backing track",
                  systemImage: session.hasBackingTrack ? "waveform" : "exclamationmark.triangle.fill")
                .lineLimit(1)
                .foregroundColor(session.hasBackingTrack ? nil : PP.warning)
        }
        .frame(maxWidth: 240)
        .disabled(session.backingLinkKey == nil || session.isPlayingAlong)
        .help("Link a saved backing track to this passage. Its bar 1 and tempo set where replays start.")
    }

    /// Keyboard shortcuts on the left; typing octave and toggles on the right.
    private var playOptions: some View {
        HStack(spacing: 14) {
            Text("[Space] \(session.mode == .playAlong ? "start/stop" : "listen")  [Return] grade  [Esc] discard  [Z]/[X] octave  [C]/[V] velocity \(session.typing.velocity)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(PP.inkMuted)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, alignment: .leading)
                .layoutPriority(-1)
            Spacer(minLength: PP.Space.s2)
            HStack(spacing: 4) {
                Button { session.shiftOctave(-1) } label: { Image(systemName: "minus") }
                    .buttonStyle(PPIconButtonStyle(kind: .tool, size: 28))
                    .help("Typing octave down (Z)")
                Text("Octave \(session.typing.octave)").font(.ppCaption).monospacedDigit().frame(width: 64)
                Button { session.shiftOctave(1) } label: { Image(systemName: "plus") }
                    .buttonStyle(PPIconButtonStyle(kind: .tool, size: 28))
                    .help("Typing octave up (X)")
            }
            HStack(spacing: 6) {
                Toggle("Mic", isOn: Binding(get: { session.micOn }, set: { session.setMicFromSwitch($0) }))
                    .toggleStyle(PPChipToggleStyle())
                    .help("Listen to an acoustic piano through the microphone")
                if session.micOn {
                    MicMeter(level: session.micLevel, gate: session.micGateLevel)
                        .frame(width: 60, height: 8)
                        .help((session.micName.isEmpty ? "Input level" : "Listening to \(session.micName)\(session.isCalibrated ? " (calibrated)" : "")")
                              + ". The tick is the noise gate: notes start only above it.")
                    gateControl
                }
            }
            KnobView(title: "Piano", value: $session.pianoVolume, range: 0...2, defaultValue: 1.4,
                     systemImage: "pianokeys")
            // Always here, so they can be set before playing along; dimmed in Wait, where
            // neither sound plays.
            Group {
                KnobView(title: "Click", value: $session.clickVolume, range: 0...1, defaultValue: 0.6,
                         systemImage: "metronome")
                KnobView(title: "Backing", value: $session.backingVolume, range: 0...1, defaultValue: 0.8,
                         systemImage: "waveform")
            }
            .opacity(session.mode == .playAlong ? 1 : 0.55)
            Toggle("Sound", isOn: $session.soundOn)
                .toggleStyle(PPChipToggleStyle())
            Toggle("Guide", isOn: $session.showGuide)
                .toggleStyle(PPChipToggleStyle())
                .help("Highlights the next key to play, with a playhead that waits on the next note")
            Toggle("Pebbles", isOn: Binding(get: { session.showsDancers }, set: { session.setDancers($0) }))
                .toggleStyle(PPChipToggleStyle())
                .help("The little dancers under the keyboard: they bob on the beat, jump on each bar and react to your notes")
            if let prompt = session.calibrationPrompt {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(prompt).font(.ppCallout.weight(.semibold))
                    Button("Cancel") { session.cancelCalibration() }
                        .buttonStyle(PPGlassButtonStyle(height: 26))
                }
                .padding(.leading, PP.Space.s3).padding(.trailing, PP.Space.s1).padding(.vertical, 3)
                .background(Capsule().fill(PP.accent.opacity(0.15)))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var notationOverlay: ScoreOverlay {
        ScoreOverlay(
            cursorQuarter: session.tutorPlayhead,
            auditioning: session.isAuditioning,
            expected: session.showGuide ? session.expected : [],
            played: session.showGuide ? session.tutorPlayedNotes : [],
            wrong: session.markedWrong,
            mistakeMeasures: session.replayMeasure.map { [$0] }
                ?? (session.tutor != nil ? session.tutorHighlight.union(session.mistakeMeasures) : (session.phase == .graded && session.report != nil ? session.mistakeMeasures : nil)),
            // The Tutor keeps its tints up during the next take: drop the green while the tempo
            // wash runs, so the two don't stack. Red bars stay as the ones to fix.
            cleanTints: !(session.showsTempoDisplay && session.tempoDisplayMoves),
            fingering: session.showFingering ? session.topStaffFingering : [],
            focusMeasures: session.markedBars
        )
    }

    private func scoreSummary(_ score: Score) -> String {
        let ts = score.timeSignature
        let staves = score.staves.count > 1 ? "both hands" : (score.staves[0] == .treble ? "treble" : "bass")
        return "\(score.measures.count) measures · \(ts.numerator)/\(ts.denominator) · \(staves) · \(Int(score.tempoBPM.rounded())) bpm"
    }

    private var statusLine: some View {
        HStack(spacing: PP.Space.s3) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(statusText).font(session.tutor == nil ? Font.ppHeadline : Font.ppCallout).lineLimit(1)
            if session.reference != nil && session.showGuide {
                Text("\(session.mode == .playAlong ? "Hit" : "Guide") \(session.guideProgress.done)/\(session.guideProgress.total)")
                    .font(.ppCallout)
                    .monospacedDigit()
                    .foregroundColor(PP.inkMuted)
            }
            if session.mode == .playAlong, let m = session.barMissCount {
                Text(m.allowed >= 1000 ? "Misses this bar: \(m.count)" : "Misses this bar: \(m.count)/\(m.allowed)")
                    .font(.ppCallout)
                    .monospacedDigit()
                    .foregroundColor(m.count == 0 ? PP.inkMuted : (m.count >= m.allowed && m.allowed < 1000 ? PP.warning : PP.ink))
            }
            // One chip at a time: a wrong note matters most, then a replay.
            if let hint = session.wrongNoteHint {
                PPFeedbackChip(kind: .mistake, text: hint)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else if session.mode == .playAlong, let summary = session.rewindSummary {
                PPFeedbackChip(kind: .warning, text: "\(session.missMode == .waitForNote ? "Stopped in" : "Replayed") \(summary)")
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            Spacer()
            if let message = session.message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.ppCaption)
                    .foregroundColor(PP.warning)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(minHeight: 36)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: session.wrongNoteHint)
    }

    private var statusColor: Color {
        if session.tutorChatAwaitingStart { return PP.inkStaff }
        if session.mode == .playAlong {
            if session.playAlongState == .idle && session.reference != nil && !session.hasBackingTrack { return PP.warning }
            switch session.playAlongState {
            case .countIn: return PP.lilac
            case .playing: return PP.accent
            case .rewinding, .waitingForNote: return PP.warning
            case .idle, .finished: break
            }
        }
        switch session.phase {
        case .waiting where session.isPlayingReference: return PP.lilac
        case .waiting: return PP.inkStaff
        case .recording: return PP.accent
        case .graded: return (session.report?.passed ?? false) ? PP.success : PP.warning
        }
    }

    private var statusText: String {
        if session.tutorChatAwaitingStart { return "Ready: press Start practice when you're ready for the count-in" }
        if session.mode == .playAlong, let text = playAlongStatus { return text }
        switch session.phase {
        case .waiting where session.isPlayingReference: return "Playing the reference… Space or Esc to stop"
        case .waiting: return "Ready: recording starts on your first note"
        case .recording where session.autoGradePending: return "Passage complete. Grading in a moment… (keep playing to continue)"
        case .recording: return "Recording… \(session.noteCount) notes. Return or Grade to finish, Esc to discard"
        case .graded where session.isPlayingReference: return "Playing the reference… Space or Esc to stop"
        case .graded: return "Graded. Play again to start a new take"
        }
    }

    private var playAlongStatus: String? {
        let backing = session.backingName.map { "with \($0)" } ?? ""
        switch session.playAlongState {
        case .idle:
            guard session.phase != .graded else { return nil }
            if session.reference == nil { return "Open a passage or MIDI file to play along" }
            if !session.hasBackingTrack { return "Missing backing track: link one with the waveform menu, or use Wait" }
            return "Play along \(backing): Space or Start to begin"
        case .countIn where session.isLeadIn:
            return "Lead-in… play from bar \(session.barLabel(session.playAlongBar ?? 0))"
        case .countIn:
            return "Count-in… bar \(session.barLabel(session.playAlongBar ?? 0)) next"
        case .playing:
            let bar = session.playAlongBar.map { session.barLabel($0) } ?? "–"
            return "Playing along: bar \(bar). Return to grade, Esc to stop"
        case .rewinding(let bar):
            return "Too many missed in bar \(session.barLabel(bar)): again from there"
        case .waitingForNote(_, let bar):
            let notes = session.expected.sorted().map { session.noteKey.spell($0).name }.joined(separator: " ")
            return "Stopped in bar \(session.barLabel(bar)): play \(notes.isEmpty ? "the next note" : notes) to carry on"
        case .finished:
            return nil
        }
    }

}

/// Input level with a tick at the noise gate, from -60 to 0 dBFS. Success-green above the gate,
/// staff-grey below it (too quiet to start a note).
struct MicMeter: View {
    let level: Float
    let gate: Float

    private func x(_ value: Float, width: CGFloat) -> CGFloat {
        let db = 20 * log10(max(Double(value), 1e-6))
        return CGFloat(min(1, max(0, (db + 60) / 60))) * width
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(PP.inkStaff.opacity(0.3))
                Capsule()
                    .fill(gate > 0 && level < gate ? PP.inkStaff : PP.success)
                    .frame(width: max(2, x(level, width: w)))
                if gate > 0 {
                    Rectangle()
                        .fill(PP.warning)
                        .frame(width: 2, height: geo.size.height + 4)
                        .offset(x: x(gate, width: w) - 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Sliders for the play-along judge. Moving one switches to Custom, starting from the
/// settings in use, and takes effect at once.
struct JudgeSettingsView: View {
    @ObservedObject var session: PlaySession

    var body: some View {
        let p = session.playAlongSettings
        VStack(alignment: .leading, spacing: 12) {
            Text("Judge").ppEyebrow()
            Text(session.strictness == .custom ? "Custom" : session.strictness.title).font(.ppHeadline)
            Text(session.strictness == .custom ? "Your own settings." : "Move a slider to customise.")
                .font(.ppCaption).foregroundColor(PP.inkMuted)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                row("Early by up to", value: p.earlyMs, range: 50...600, step: 10, unit: "ms") { $0.earlyMs = $1 }
                row("Late by up to", value: p.lateMs, range: 80...900, step: 10, unit: "ms") { $0.lateMs = $1 }
                row("Extra lateness (mic)", value: p.micExtraLateMs, range: 0...300, step: 10, unit: "ms") { $0.micExtraLateMs = $1 }
                row("Extra lateness (keys)", value: p.keysExtraLateMs, range: 0...300, step: 10, unit: "ms") { $0.keysExtraLateMs = $1 }
                GridRow {
                    Text("Misses allowed per bar")
                    HStack(spacing: PP.Space.s2) {
                        Text(p.maxMissesPerBar > 8 ? "any" : "\(p.maxMissesPerBar)").monospacedDigit().frame(width: 36, alignment: .leading)
                        PPStepper(value: intBinding(\.maxMissesPerBar, cap: 8), in: 0...9)
                    }
                    Text("")
                }
                row("…and at most this share of the bar", value: p.maxMissFraction * 100, range: 0...100, step: 5, unit: "%") {
                    $0.maxMissFraction = $1 / 100
                }
                GridRow {
                    Text("Replay after missing in a row")
                    HStack(spacing: PP.Space.s2) {
                        Text(p.maxConsecutiveMisses > 8 ? "never" : "\(p.maxConsecutiveMisses)").monospacedDigit().frame(width: 36, alignment: .leading)
                        PPStepper(value: intBinding(\.maxConsecutiveMisses, cap: 8), in: 1...9)
                    }
                    Text("")
                }
                row("Notes of a chord needed", value: p.minChordCoverage * 100, range: 25...100, step: 25, unit: "%") {
                    $0.minChordCoverage = $1 / 100
                }
            }
            Text("A bar replays when its misses go over both limits, or after the misses in a row. Wrong extra notes never stop the music.")
                .font(.ppCaption).foregroundColor(PP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.ppCallout)
        .foregroundColor(PP.ink)
        .tint(PP.accent)
        .padding(PP.Space.s6)
        .frame(width: 460)
    }

    private func row(_ title: String, value: Double, range: ClosedRange<Double>, step: Double, unit: String,
                     set: @escaping (inout Rubric.PlayAlong, Double) -> Void) -> some View {
        GridRow {
            Text(title)
            PPSlider(value: Binding(get: { min(range.upperBound, max(range.lowerBound, value)) },
                                    set: { v in edit { set(&$0, v) } }),
                     range: range, step: step)
                .frame(width: 160)
                .accessibilityLabel(title)
            Text("\(Int(value.rounded())) \(unit)").monospacedDigit().frame(width: 60, alignment: .leading)
        }
    }

    /// 9 on the stepper means "no limit".
    private func intBinding(_ path: WritableKeyPath<Rubric.PlayAlong, Int>, cap: Int) -> Binding<Int> {
        Binding(get: { min(cap + 1, session.playAlongSettings[keyPath: path]) },
                set: { v in edit { $0[keyPath: path] = v > cap ? 10_000 : v } })
    }

    private func edit(_ change: (inout Rubric.PlayAlong) -> Void) {
        session.beginCustomStrictness()
        var p = session.customPlayAlong
        change(&p)
        session.customPlayAlong = p
    }
}

struct ReportView: View {
    let report: GradeReport?
    let phase: PlaySession.Phase

    var body: some View {
        if let report {
            VStack(alignment: .leading, spacing: PP.Space.s4) {
                Text("Result").ppEyebrow()
                HStack(alignment: .center, spacing: PP.Space.s3) {
                    Image(systemName: report.passed ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(report.passed ? PP.success : PP.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.passed ? "Passed" : "Not yet").font(.ppTitle)
                        Text("\(report.rubricLevel) rubric").font(.ppCallout).foregroundColor(PP.inkMuted)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: PP.Space.s2, verticalSpacing: PP.Space.s2) {
                    ForEach(report.levels, id: \.check) { level in
                        GridRow(alignment: .firstTextBaseline) {
                            Image(systemName: symbol(level.passed))
                                .foregroundColor(color(level.passed))
                                .accessibilityLabel(level.passed == nil ? "Not graded" : (level.passed! ? "Passed" : "Not passed"))
                            Text(level.check.rawValue.capitalized).font(.ppCallout.weight(.semibold))
                            Text(level.detail + (level.passed == nil ? "  (not graded)" : ""))
                                .font(.ppCallout)
                                .foregroundColor(level.passed == nil ? PP.inkMuted : PP.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if report.notes.ignoredLeading + report.notes.ignoredTrailing > 0 {
                    Text("Ignored \(report.notes.ignoredLeading) note(s) before and \(report.notes.ignoredTrailing) after the passage.")
                        .font(.ppCaption).foregroundColor(PP.inkMuted)
                }
                if report.flags.isEmpty {
                    Label("No mistakes flagged.", systemImage: "sparkles")
                        .font(.ppCallout).foregroundColor(PP.success)
                } else {
                    Text("To fix").ppEyebrow()
                    ScrollView {
                        VStack(alignment: .leading, spacing: PP.Space.s2) {
                            ForEach(Array(report.flags.enumerated()), id: \.offset) { _, flag in
                                HStack(alignment: .firstTextBaseline, spacing: PP.Space.s2) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(PP.mistake)
                                        .accessibilityHidden(true)
                                    Text(flag.message)
                                        .font(.ppCallout)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: PP.Space.s3) {
                Text(phase == .recording ? "Listening" : "How a take works").ppEyebrow()
                Text(phase == .recording ? "Keep playing. Return grades the take, Esc discards it." : "Press Space (or Listen) to hear the passage, then play it on a Bluetooth MIDI piano, a piano with the mic on, or the computer keyboard. The playhead waits on the next note, and the highlighted key shows what to play. While you hold a wrong key, a red circle on the staff shows where you are.")
                    .font(.ppBody)
                    .foregroundColor(PP.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func symbol(_ passed: Bool?) -> String {
        switch passed {
        case .some(true): return "checkmark.circle.fill"
        case .some(false): return "xmark.circle.fill"
        case .none: return "minus.circle"
        }
    }

    private func color(_ passed: Bool?) -> Color {
        switch passed {
        case .some(true): return PP.success
        case .some(false): return PP.mistake
        case .none: return PP.inkMuted
        }
    }
}
#endif
