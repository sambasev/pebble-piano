#if os(macOS)
import PianoGraderCore
import PianoLessons
import PianoPadState
import SwiftUI

// First launch: a short setup that ends on the first lesson page. See
// docs/design/beginner-journeys.md (B0). The learner is created only at the end, so the
// launch screen stays up throughout and Back works from any step.

/// The answers collected during setup.
struct SetupAnswers {
    var name = ""
    var avatar = Learner.defaultAvatar
    var kind = Learner.Kind.adult
    var level: Learner.Level? = .beginner
    var input: InputSource = .microphone
    var persona = "alex"
    var goalSong = GoalSongs.defaultID
}

extension PlaySession {
    /// Creates the learner from setup, saves their answers, and opens the first lesson page.
    func finishSetup(_ answers: SetupAnswers) {
        guard addLearner(name: answers.name, avatar: answers.avatar, kind: answers.kind, level: answers.level) != nil else {
            return
        }
        // Children get Alex; a grown-up can choose Kriti later under For grown-ups.
        learnerSettings.persona = answers.kind == .child ? "alex" : answers.persona
        learnerSettings.goalSong = answers.goalSong
        learnerSettings.inputSource = answers.input.rawValue
        learnerSettings.onboardedAt = Date()
        saveLearnerSettings()
        if let learner {
            try? learnerStore.history(for: learner.id).recordSetup(started: setupStartedAt ?? Date(), finished: Date())
        }
        Usage.event("Setup.finished", ["learner": answers.kind.rawValue, "input": answers.input.rawValue,
                                       "teacher": learnerSettings.persona ?? "alex", "goalSong": answers.goalSong],
                    value: Date().timeIntervalSince(setupStartedAt ?? Date()))
        setupStartedAt = nil
        if answers.input == .microphone {
            if !micOn { micOn = true }
        } else if answers.input == .computerKeyboard, micOn {
            micOn = false
        }
        startLearning()
    }

    /// Switches to Learn and opens the page to do next.
    func startLearning() {
        tab = .learn
        // After the tab change has run (it's deferred a turn), open the page.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lessonRunner.arrive()
            if let id = self.lessonRunner.nextPageID { self.lessonRunner.open(id) }
        }
    }
}

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, learner, piano, input, teacher, goal, ready
    }

    @EnvironmentObject var session: PlaySession
    /// Set when shown as a sheet (adding another learner): Cancel on the first step.
    var onCancel: (() -> Void)? = nil
    /// Called after the learner is created (the sheet closes).
    var onFinish: (() -> Void)? = nil
    @State private var step = Step.welcome
    @State private var answers = SetupAnswers()
    /// The answer to "Are you at a piano?"; nil until answered. No means the computer
    /// keyboard, and the input step is skipped.
    @State private var atPiano: Bool?
    private var noPiano: Bool { atPiano == false }
    /// The input step's choice was made (microphone or Bluetooth MIDI).
    @State private var inputChosen = false
    /// A teacher or goal song was tapped on this step: Continue counts down so the pick
    /// carries on by itself (with a moment to change your mind).
    @State private var picked = false

    private var trimmedName: String { answers.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isChild: Bool { answers.kind == .child }
    /// "you", or the child's name ("your child" before it's typed) when a parent is setting up.
    private var learnerWord: String {
        guard isChild else { return "you" }
        return trimmedName.isEmpty ? "your child" : trimmedName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s6) {
            if step != .welcome { progressDots }
            Group {
                switch step {
                case .welcome: welcome
                case .learner: learnerStep
                case .piano: pianoStep
                case .input: inputStep
                case .teacher: teacherStep
                case .goal: goalStep
                case .ready: readyStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
            footer
        }
        .frame(width: 560)
        .animation(.easeInOut(duration: 0.18), value: step)
        .onAppear { session.setupStartedAt = Date() }
        .onChange(of: step) { _ in picked = false }
        .onDisappear { if session.calibrationPrompt != nil { session.cancelCalibration() } }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: PP.Space.s4) {
            Text("Welcome to PerfectPiano").ppEyebrow()
            Text("Let's get you playing in about 15 minutes.").font(.ppTitle)
                .fixedSize(horizontal: false, vertical: true)
            Text("A few quick questions first. Then you'll find Middle C and play your first notes, and PerfectPiano will listen and help as you go.")
                .font(.ppBody).foregroundColor(PP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text("This beta sends anonymous usage stats (which screens are used, and for how long) to help improve it. Never audio or names. Turn it off under PerfectPiano ▸ Share Anonymous Usage Data.")
                .font(.ppCaption).foregroundColor(PP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var learnerStep: some View {
        VStack(alignment: .leading, spacing: PP.Space.s4) {
            Text("Who's learning?").font(.ppTitle)
            PPSegmented(selection: $answers.kind, [
                (Learner.Kind.adult, "Me (adult)"),
                (Learner.Kind.child, "A child")
            ])
            .accessibilityLabel("Learner")
            if isChild {
                Text("You're setting this up for your child. Stay close for the first few minutes; after that they can carry on by themselves, and you can check how they're doing under For grown-ups.")
                    .font(.ppCallout).foregroundColor(PP.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField(isChild ? "Child's name" : "Your name", text: $answers.name)
                .ppField()
                .font(.ppBody)
                .onSubmit(next)
            VStack(alignment: .leading, spacing: PP.Space.s2) {
                Text("Avatar").ppEyebrow()
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: PP.Space.s2), count: 12),
                          alignment: .leading, spacing: PP.Space.s2) {
                    ForEach(LearnerAvatars.all, id: \.self) { symbol in
                        Button { answers.avatar = symbol } label: {
                            AvatarCircle(symbol: symbol, kind: answers.kind, size: 36, selected: answers.avatar == symbol)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                    }
                }
            }
            VStack(alignment: .leading, spacing: PP.Space.s2) {
                Text(isChild ? "Has \(learnerWord) played before?" : "Have you played before?").ppEyebrow()
                PPSegmented(selection: $answers.level, [
                    (Learner.Level?.some(.beginner), "Never"),
                    (Learner.Level?.some(.basics), "A little"),
                    (Learner.Level?.none, "Not sure")
                ])
                .accessibilityLabel("Played before")
                if answers.level == .basics {
                    Text("Unit 1 starts from the beginning; it'll go quickly. A placement check comes later.")
                        .font(.ppCaption).foregroundColor(PP.inkMuted)
                }
            }
        }
    }

    private var pianoStep: some View {
        VStack(alignment: .leading, spacing: PP.Space.s4) {
            Text(isChild ? "Is \(learnerWord) at a piano or keyboard right now?" : "Are you at a piano or keyboard right now?")
                .font(.ppTitle).fixedSize(horizontal: false, vertical: true)
            Text(isChild
                 ? "PerfectPiano listens to real playing. Without one, \(learnerWord) can still learn on the computer: the letter keys and the on-screen keys play notes."
                 : "PerfectPiano listens to real playing. Without one, you can still learn on the computer: the letter keys and the on-screen keys play notes.")
                .font(.ppBody).foregroundColor(PP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: PP.Space.s3) {
                choice("Yes", systemImage: "pianokeys", selected: atPiano == true) {
                    atPiano = true
                    if answers.input == .computerKeyboard {
                        answers.input = .microphone
                        inputChosen = false
                    }
                    next()
                }
                choice("Not right now", systemImage: "keyboard", selected: atPiano == false) {
                    atPiano = false
                    answers.input = .computerKeyboard
                    next()
                }
            }
        }
    }

    /// Two ways to hear a piano, chosen explicitly: the microphone, or Bluetooth MIDI.
    private var inputStep: some View {
        VStack(alignment: .leading, spacing: PP.Space.s4) {
            Text("How should PerfectPiano hear \(isChild ? learnerWord : "you")?").font(.ppTitle)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: PP.Space.s3) {
                inputCard(title: "Microphone", systemImage: "mic.fill", source: .microphone,
                          detail: "For an acoustic piano, or a digital piano playing through its speakers. Your Mac listens; the audio never leaves it.")
                inputCard(title: "Bluetooth MIDI", systemImage: "dot.radiowaves.left.and.right", source: .midi,
                          detail: "For a digital piano or keyboard with Bluetooth MIDI. Notes arrive exactly, even with the volume down.")
            }
            if inputChosen && answers.input == .microphone {
                micSetup
            } else if inputChosen && answers.input == .midi {
                bluetoothStatus
            }
        }
    }

    private func inputCard(title: String, systemImage: String, source: InputSource, detail: String) -> some View {
        let selected = inputChosen && answers.input == source
        return Button {
            answers.input = source
            inputChosen = true
            switch source {
            case .microphone:
                if !session.micOn { session.micOn = true } // asks for permission now
            case .midi:
                if session.micOn { session.micOn = false }
                session.startMIDI()
            case .computerKeyboard:
                break
            }
        } label: {
            VStack(alignment: .leading, spacing: PP.Space.s2) {
                Image(systemName: systemImage).font(.system(size: 24, weight: .semibold))
                    .foregroundColor(selected ? PP.accent : PP.ink)
                Text(title).font(.ppHeadline)
                Text(detail).font(.ppCallout).foregroundColor(PP.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(PP.Space.s4)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: PP.Radius.md, style: .continuous)
                .fill(selected ? PP.accent.opacity(0.12) : PP.surfaceRaised.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: PP.Radius.md, style: .continuous)
                .strokeBorder(selected ? PP.accent : PP.inkStaff.opacity(0.35), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Bluetooth MIDI: connected, or how to connect. Updates by itself when the piano pairs.
    @ViewBuilder
    private var bluetoothStatus: some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            if session.midiSources.isEmpty {
                Text("1. Turn on Bluetooth (or Bluetooth MIDI) on the piano.\n2. Press Connect and choose the piano in the window that opens.")
                    .font(.ppCallout).fixedSize(horizontal: false, vertical: true)
                Button("Connect a Bluetooth piano…") { session.showBluetoothMIDIPairing() }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
            } else {
                Label("Connected: " + session.midiSources.joined(separator: ", "), systemImage: "checkmark.circle.fill")
                    .font(.ppHeadline).foregroundColor(PP.success)
                Text("Play a note to check: it lights up on the keyboard in your first lesson.")
                    .font(.ppCallout).foregroundColor(PP.inkMuted)
            }
            if !session.ignoredMIDISources.isEmpty {
                Text("Not a piano, so ignored: " + session.ignoredMIDISources.joined(separator: ", "))
                    .font(.ppCaption).foregroundColor(PP.inkMuted)
            }
        }
    }

    /// A live level so the learner sees the mic hears them.
    private var micCheck: some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            Text(session.micOn ? "Play any note: the bar should jump." : "Allow the microphone when your Mac asks.")
                .font(.ppCallout).foregroundColor(PP.inkMuted)
            levelBar
        }
    }

    private var levelBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(PP.surfaceRaised)
                Capsule().fill(PP.success)
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, session.micLevel * 4))))
            }
        }
        .frame(height: 10)
        .animation(.linear(duration: 0.08), value: session.micLevel)
    }

    /// The microphone: which input, a live level, and the room's noise level (3 seconds of
    /// quiet), which sets the threshold a note must pass to count.
    private var micSetup: some View {
        VStack(alignment: .leading, spacing: PP.Space.s3) {
            AudioDevicesView(showsOutput: true)
            micCheck
            if let prompt = session.calibrationPrompt {
                HStack(spacing: PP.Space.s2) {
                    ProgressView().controlSize(.small)
                    Text(prompt).font(.ppHeadline)
                }
            } else if let outcome = session.noiseOutcome {
                noiseCard(outcome)
                Button("Measure again") { session.measureSilence() }
                    .buttonStyle(PPGlassButtonStyle())
            } else {
                Text("Now the room: stay quiet for 3 seconds so PerfectPiano learns its background noise and only counts real notes.")
                    .font(.ppCallout).foregroundColor(PP.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Measure room noise") { session.measureSilence() }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                    .disabled(!session.micOn)
            }
        }
    }

    private func noiseCard(_ outcome: PlaySession.NoiseOutcome) -> some View {
        let (symbol, color, text): (String, Color, String) = {
            switch outcome {
            case .set(let gate, _):
                return ("checkmark.circle.fill", PP.success,
                        String(format: "Room noise measured. Notes louder than %.0f dBFS count.", gate))
            case .tooNoisy:
                return ("exclamationmark.triangle.fill", PP.warning,
                        "Too noisy to measure. Turn off a fan or music, then measure again, or carry on and PerfectPiano will judge the room as it listens.")
            case .silent:
                return ("xmark.circle.fill", PP.mistake,
                        "Nothing came in from the microphone. Check the input above, and that the Mac may use the microphone.")
            }
        }()
        return HStack(alignment: .top, spacing: PP.Space.s3) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundColor(color)
            Text(text).font(.ppCallout).fixedSize(horizontal: false, vertical: true)
        }
        .padding(PP.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: PP.Radius.sm, style: .continuous).fill(color.opacity(0.10)))
    }

    private var teacherStep: some View {
        VStack(alignment: .leading, spacing: PP.Space.s4) {
            Text(isChild ? (trimmedName.isEmpty ? "Your child's teacher" : "\(trimmedName)'s teacher") : "Choose a teacher").font(.ppTitle)
            Text(isChild ? "Alex keeps things relaxed and encouraging. You can choose the strict teacher, Kriti, later under For grown-ups."
                         : "You can change teacher later on the unit page.")
                .font(.ppBody).foregroundColor(PP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: PP.Space.s3) {
                teacherCard(id: "alex", name: "Alex", tag: "Relaxed",
                            lines: ["Lets small slips go", "Moves on when it's mostly right", "Short, encouraging tips"])
                if !isChild {
                    teacherCard(id: "kriti", name: "Kriti", tag: "Strict",
                                lines: ["Notices every slip", "Wants it clean before moving on", "Specific corrections"])
                }
            }
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: PP.Space.s4) {
            Text(isChild ? "Pick a song for \(learnerWord) to work towards" : "Pick a song to work towards").font(.ppTitle)
                .fixedSize(horizontal: false, vertical: true)
            Text("By the end of Unit 1, \(learnerWord == "you" ? "you'll" : "\(learnerWord) will") play it.")
                .font(.ppBody).foregroundColor(PP.inkMuted)
            VStack(spacing: PP.Space.s2) {
                ForEach(GoalSongs.all) { song in
                    Button {
                        answers.goalSong = song.id
                        picked = true
                    } label: {
                        HStack(spacing: PP.Space.s3) {
                            Image(systemName: answers.goalSong == song.id ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(answers.goalSong == song.id ? PP.accent : PP.inkMuted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).font(.ppHeadline)
                                Text(song.blurb).font(.ppCallout).foregroundColor(PP.inkMuted)
                            }
                            Spacer()
                            Color.clear.frame(width: PP.Size.compact) // room for the play button
                        }
                        .padding(PP.Space.s3)
                        .background(RoundedRectangle(cornerRadius: PP.Radius.sm, style: .continuous)
                            .fill(answers.goalSong == song.id ? PP.accent.opacity(0.12) : PP.surfaceRaised.opacity(0.6)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .trailing) {
                        PreviewButton(id: "goal:" + song.id, title: song.title) {
                            PlaySession.bundledResource("Lessons/unit1/" + Block.SongChallenge.goalSongPath(song.id)).map { ($0, nil) }
                        }
                        .padding(.trailing, PP.Space.s3)
                    }
                }
            }
        }
        // Moving on (or away) ends the preview.
        .onDisappear { session.preview.stop() }
    }

    private var readyStep: some View {
        let song = GoalSongs.song(answers.goalSong)?.title ?? "your song"
        return VStack(alignment: .leading, spacing: PP.Space.s4) {
            Text("All set").ppEyebrow()
            Text(isChild ? "\(trimmedName) is ready to play." : "You're ready to play, \(trimmedName).")
                .font(.ppTitle).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: PP.Space.s2) {
                summaryRow("pianokeys", inputSummary)
                summaryRow("person.fill", "Teacher: \(answers.persona == "kriti" && !isChild ? "Kriti (strict)" : "Alex (relaxed)")")
                summaryRow("flag.checkered", "Goal: \(song)")
            }
            Text(isChild ? "First up: \(trimmedName) finds Middle C. Sit with them for this first page." : "First up: find Middle C.")
                .font(.ppHeadline).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inputSummary: String {
        switch answers.input {
        case .midi: return "Listening over Bluetooth MIDI" + (session.midiSources.first.map { " (\($0))" } ?? "")
        case .microphone: return "Listening through the microphone"
        case .computerKeyboard: return "Playing on the computer keyboard (A S D F… are white keys)"
        }
    }

    // MARK: Pieces

    private var progressDots: some View {
        HStack(spacing: PP.Space.s1) {
            ForEach(Step.allCases.dropFirst(), id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? PP.accent : PP.inkMuted.opacity(0.25))
                    .frame(width: s == step ? 22 : 8, height: 8)
            }
        }
        .accessibilityLabel("Step \(step.rawValue) of \(Step.allCases.count - 1)")
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back", action: back)
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
            } else if let onCancel {
                Button("Cancel", action: onCancel)
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            if step != .piano {
                if let seconds = autoSeconds, canContinue {
                    TimedContinueButton(title: primaryTitle, seconds: seconds, action: next)
                        .id(autoKey)
                } else {
                    Button(primaryTitle, action: next)
                        .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canContinue)
                }
            }
        }
    }

    /// Steps whose Continue counts down: information to read, a check that passed, or a
    /// pick just made. Typing a name, choosing an input and a failed check stay manual.
    private var autoSeconds: Double? {
        switch step {
        case .welcome:
            // Also when adding another learner: Cancel still works, and hovering pauses.
            return AutoAdvance.seconds(.setupInfo)
        case .input:
            guard inputChosen, session.calibrationPrompt == nil else { return nil }
            switch answers.input {
            case .microphone:
                if case .set = session.noiseOutcome { return AutoAdvance.seconds(.checkPassed) }
                return nil
            case .midi:
                return session.midiSources.isEmpty ? nil : AutoAdvance.seconds(.checkPassed)
            case .computerKeyboard:
                return nil
            }
        case .teacher, .goal:
            return picked ? AutoAdvance.seconds(.choiceMade) : nil
        case .ready:
            return AutoAdvance.seconds(.setupInfo, child: isChild)
        case .learner, .piano:
            return nil
        }
    }

    /// A new pick, input or check result starts a fresh count.
    private var autoKey: String {
        "\(step.rawValue)-\(answers.persona)-\(answers.goalSong)-\(answers.input.rawValue)-\(session.midiSources.count)-\(String(describing: session.noiseOutcome))"
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Get started"
        case .ready: return "Start lesson 1"
        default: return "Continue"
        }
    }

    private var canContinue: Bool {
        switch step {
        case .learner: return !trimmedName.isEmpty
        case .input:
            guard inputChosen, session.calibrationPrompt == nil else { return false }
            return answers.input == .microphone || (answers.input == .midi && !session.midiSources.isEmpty)
        default: return true
        }
    }

    private func next() {
        guard canContinue else { return }
        if step == .ready {
            answers.name = trimmedName
            session.finishSetup(answers)
            onFinish?()
            return
        }
        var target = Step(rawValue: step.rawValue + 1) ?? .ready
        if target == .input && noPiano { target = .teacher }
        step = target
    }

    private func back() {
        var target = Step(rawValue: step.rawValue - 1) ?? .welcome
        if target == .input && noPiano { target = .piano }
        if session.calibrationPrompt != nil { session.cancelCalibration() }
        step = target
    }

    private func choice(_ title: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: PP.Space.s2) {
                Image(systemName: systemImage).font(.system(size: 26, weight: .semibold))
                Text(title).font(.ppHeadline)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(RoundedRectangle(cornerRadius: PP.Radius.md, style: .continuous)
                .fill(selected ? PP.accent.opacity(0.14) : PP.surfaceRaised.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: PP.Radius.md, style: .continuous)
                .strokeBorder(selected ? PP.accent : PP.inkStaff.opacity(0.35), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func teacherCard(id: String, name: String, tag: String, lines: [String]) -> some View {
        let selected = answers.persona == id
        return Button {
            answers.persona = id
            picked = true
        } label: {
            VStack(alignment: .leading, spacing: PP.Space.s2) {
                HStack {
                    Text(name).font(.ppHeadline)
                    Spacer()
                    Text(tag).font(.ppCaption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(selected ? PP.accent : PP.lilac))
                        .foregroundColor(selected ? PP.onAccent : PP.ink)
                }
                ForEach(lines, id: \.self) { line in
                    Label(line, systemImage: "checkmark").font(.ppCallout).foregroundColor(PP.inkMuted)
                }
            }
            .padding(PP.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: PP.Radius.md, style: .continuous)
                .fill(selected ? PP.accent.opacity(0.12) : PP.surfaceRaised.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: PP.Radius.md, style: .continuous)
                .strokeBorder(selected ? PP.accent : PP.inkStaff.opacity(0.35), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func summaryRow(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.ppCallout).foregroundColor(PP.ink)
    }
}
#endif
