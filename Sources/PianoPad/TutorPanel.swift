#if os(macOS)
import SwiftUI
import PianoLessons
import PianoPadState

struct TutorPanel: View {
    @EnvironmentObject var session: PlaySession
    @State private var settings = false
    /// Start the tutor's next step by itself after a short countdown (hover pauses it).
    @AppStorage("PianoPad.tutor.autoContinue") private var autoContinue = true
    /// Lesson, or Ask your tutor (adults only). Kept from piece to piece.
    @AppStorage("PianoPad.tutor.asking") private var asking = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Piece tutor").font(.ppHeadline)
                Spacer()
                if asking && session.canAskTutor && !session.tutorChat.turns.isEmpty {
                    Button { session.resetTutorChat() } label: { Image(systemName: "square.and.pencil") }
                        .buttonStyle(PPIconButtonStyle())
                        .accessibilityLabel("New chat")
                        .help("New chat")
                }
                if !session.tutorChatIsChild { Button("AI settings") { settings = true } }
            }
            if session.canAskTutor {
                PPSegmented(selection: $asking, [
                    (false, "Lesson"),
                    (true, "Ask")
                ])
                .accessibilityLabel("")
                .help("Ask your tutor about this piece, the book page, or anything about music")
            }
            if asking && session.canAskTutor {
                TutorChatView()
            } else {
                lesson
            }
        }.sheet(isPresented: $settings) { AISettingsView { settings = false }.ppDefaultButtons() }
    }

    @ViewBuilder private var lesson: some View {
            if let engine = session.tutor {
                Text(session.tutorAI.isEmpty ? session.tutorText : session.tutorAI)
                if session.tutorBusy { ProgressView("Preparing explanation…") }
                if let note = session.tutorNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                if session.tutorPlanning {
                    ProgressView(session.tutorPlanNote ?? "Planning your lesson…")
                    Button("Use a quick plan instead") { session.useQuickTutorPlan() }
                        .help("Plan the lesson in code now, without waiting for Muse Spark")
                } else {
                    current(engine)
                }
                Button("End tutoring") { session.pauseTutorChatCoaching(); session.endTutoring() }
            } else if let readiness = session.tutorReadiness {
                ReadinessCard(readiness: readiness)
            } else if session.reference?.notes.isEmpty == false {
                if let saved = session.savedTutorProgress {
                    // A lesson under way: carry on from where it was left.
                    let done = saved.completedSteps.count
                    let total = saved.stepCount.map { " of \($0)" } ?? ""
                    Text(saved.mastered ? "You've passed this piece with the tutor\(saved.lastStars.map { " (\($0) ★)" } ?? "")."
                         : "\(session.learner.map { "\($0.name)'s" } ?? "Your") lesson on this piece is under way: \(done)\(total) steps done.")
                        .font(.callout)
                    Button {
                        session.beginTutoring(planLesson: true)
                    } label: {
                        Label(saved.mastered ? "Open the lesson" : "Continue the lesson", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))
                    Button("Start the lesson over") { session.beginTutoring(planLesson: true, startOver: true) }
                        .help("Same plan, from the first step; your progress on it is forgotten")
                } else {
                    Button { session.beginTutoring(planLesson: true) } label: {
                        Label("Teach me this piece", systemImage: "graduationcap.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))
                        .help("Plan a lesson for this piece: listen, new notes, phrase by phrase, then perform")
                }
            }
            if session.reference?.notes.isEmpty == false && session.score != nil {
                MarkedBarsSection()
            }
    }

    @ViewBuilder private func current(_ engine: PiecePracticeEngine) -> some View {
        let e = engine.exercise
        if let stars = engine.lastStars {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < stars ? "star.fill" : "star").foregroundColor(.yellow)
                }
                Text(engine.mastered ? "Piece passed" : "Last performance").font(.caption).padding(.leading, 4)
            }
        }
        if session.tutorAttempt == nil {
            Text(readyText(e)).font(.callout)
        }
        if autoStarts(engine) {
            // A new step or a new comment starts a new count.
            TimedContinueButton(title: startLabel(e), seconds: countdownSeconds) { session.startTutorExercise() }
                .frame(maxWidth: .infinity)
                .id(countdownID(engine))
        } else {
            Button {
                session.startTutorExercise()
            } label: {
                Label(startLabel(e), systemImage: e.kind == .listen ? "speaker.wave.2.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))
            .disabled(session.phase == .recording)
        }
        if session.tutorCanStopHere {
            Button {
                session.tutorStopHere()
            } label: {
                Label("Stop here and plan from what I played", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .help("Only the bars played so far are graded; the tutor teaches the rest from the start")
        } else if session.tutorAttempt == nil && (e.kind == .placement || e.kind == .assessment) {
            HStack {
                Text("Skip it and learn").font(.callout)
                Button("Note by note") { session.tutorSkipAssessment(pace: .noteByNote) }
                    .help("Each phrase in wait mode first, then slowly in time")
                Button("Passage by passage") { session.tutorSkipAssessment(pace: .passageByPassage) }
                    .help("Each phrase slowly in time, then at full speed; note by note only where it goes wrong")
            }
        }
        if engine.plan != nil {
            PPSegmented(selection: Binding(get: { engine.pace }, set: { session.tutorSetPace($0) }), [
                (Pace.noteByNote, "Note by note"),
                (Pace.passageByPassage, "Passage by passage")
            ])
            .accessibilityLabel("New passages")
            .font(.caption)
            .disabled(session.phase == .recording)
            .help("How the tutor teaches phrases you haven't shown it yet")
        }
        Toggle("Start the next step by itself", isOn: $autoContinue)
            .font(.caption)
            .help("After each step, the next one starts after a short countdown. Hover over the button to pause it.")
        HStack {
            Button("Hear it first") { session.startListening() }
            Button("Try again") { session.retryTutorExercise() }
            Button("Skip step") { session.tutorSkip() }
        }
        HStack {
            Button("What went wrong?") { session.askTutor("What went wrong?", userAsked: true) }
            Button("Why this exercise?") { session.askTutor("Why this exercise?", userAsked: true) }
        }.disabled(session.phase == .recording)
        HStack {
            if engine.isFollowingPlan {
                Button("Assess me instead") { session.tutorAssessInstead() }
                    .help("Play the whole piece now; the tutor drills what needs it")
            } else {
                Button("Reassess piece") { session.tutorLeaveAttempt(); session.tutor?.reassess(); session.startTutorExercise() }
            }
            Menu("More") {
                if !engine.steps.isEmpty {
                    Button("Back to the lesson plan") { session.tutorJump(to: 0) }
                }
                Button("Learn whole piece note by note") { session.tutorLeaveAttempt(); session.tutor?.learnNotes(); session.startTutorExercise() }
                Button("Plan again with Muse Spark") { session.planTutorLesson(fresh: true) }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        if let note = session.tutorPlanNote {
            Text(note).font(.caption).foregroundColor(.secondary)
        }
    }

    /// Between steps (before the first try, or once a try is graded), not while the piece is
    /// playing or the tutor is still writing its comment, and not once the piece is passed.
    private func autoStarts(_ engine: PiecePracticeEngine) -> Bool {
        autoContinue && !session.tutorChatCoaching && !engine.mastered && !session.isAuditioning && !session.tutorBusy && !session.tutorPlanning
            && !session.tutorHeardNothing
            && session.phase != .recording && (session.tutorAttempt == nil || session.phase == .graded)
    }

    /// One second (1.5 for a child): the comment stays on screen while the step runs.
    private var countdownSeconds: Double {
        session.learner?.kind == .child ? 1.5 : 1
    }

    private func countdownID(_ engine: PiecePracticeEngine) -> String {
        "\(engine.stepIndex ?? -1)|\(engine.exercise.title)|\(engine.exercise.measures)|\(session.tutorText)|\(session.tutorAI)"
    }

    private func startLabel(_ e: PracticeExercise) -> String {
        switch e.kind {
        case .assessment: return "Start assessment"
        case .listen: return "Listen"
        case .newNote: return "Find the note"
        case .perform: return "Perform"
        case .placement: return "Play it for me"
        default: return "Start step"
        }
    }

    private func readyText(_ e: PracticeExercise) -> String {
        switch e.kind {
        case .listen: return "Press Listen and follow the music."
        case .newNote: return "Press Find the note, then play the highlighted key."
        case .notes: return "Press Start step: the music waits for each note\(e.hand == nil ? "" : "—play only the \(e.hand == .left ? "left" : "right") hand")."
        case .perform: return "Press Perform, then play the whole piece after the count-in."
        case .placement: return "Play the whole piece once, as well as you can. Parts you play cleanly are ticked off. Stop whenever you like, or skip it."
        default: return "Ready when you are: press \(startLabel(e)), then play after the count-in\(e.hand == nil ? "" : " (\(e.hand == .left ? "left" : "right") hand only)")."
        }
    }
}

/// The step being worked on, large and above the music where the eyes already are. The full
/// plan stays folded away behind the Plan button.
struct TutorStepBanner: View {
    @EnvironmentObject var session: PlaySession
    let engine: PiecePracticeEngine
    @State private var showsPlan = false

    var body: some View {
        let e = engine.exercise
        HStack(alignment: .center, spacing: PP.Space.s4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow).font(.ppEyebrow).foregroundColor(PP.accent)
                Text(headline(e))
                    .font(.system(size: 24, weight: .bold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(details(e)).font(.ppCallout).monospacedDigit().foregroundColor(PP.inkMuted)
                if let tip = tip(for: e) {
                    Text(tip).font(.ppCallout).foregroundColor(PP.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if !engine.steps.isEmpty {
                Button {
                    showsPlan.toggle()
                } label: {
                    Label("Plan \(engine.completedSteps.count)/\(engine.steps.count)", systemImage: "list.bullet")
                        .monospacedDigit()
                }
                .buttonStyle(PPGlassButtonStyle(height: PP.Size.compact))
                .fixedSize()
                .help("See the whole lesson plan, or go to another step")
                .popover(isPresented: $showsPlan, arrowEdge: .bottom) {
                    PlanChecklist(engine: engine) { showsPlan = false }
                        .environmentObject(session)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppGlass(cornerRadius: PP.Radius.lg, padding: PP.Space.s3)
    }

    private var eyebrow: String {
        engine.stepIndex.map { "STEP \($0 + 1) OF \(engine.steps.count)" } ?? "EXTRA PRACTICE"
    }

    /// "Slowly, in time · First Joy tune".
    private func headline(_ e: PracticeExercise) -> String {
        guard let label = e.label else { return e.title }
        return "\(e.title) · \(label)"
    }

    /// "Bars 6–13 · 70% speed · Clean runs 0/1".
    private func details(_ e: PracticeExercise) -> String {
        var parts: [String] = []
        if e.kind != .newNote {
            parts.append(e.measures.count == 1 ? "Bar \(e.measures.lowerBound)" : "Bars \(e.measures.lowerBound)–\(e.measures.upperBound)")
        }
        if e.isTimed { parts.append("\(Int(e.tempoPercent))% speed") }
        if e.isTimed || e.isWaitMode { parts.append("Clean runs \(engine.cleanStreak)/\(engine.needed)") }
        return parts.joined(separator: " · ")
    }

    private func tip(for e: PracticeExercise) -> String? {
        guard let plan = engine.plan, let label = e.label else { return nil }
        return plan.phrases.first { $0.label == label }?.tip
    }
}

/// Before a piece: the stock lessons that teach what it needs, with Open, or carry on anyway.
private struct ReadinessCard: View {
    @EnvironmentObject var session: PlaySession
    let readiness: Readiness

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Before \(session.tutorTitle)").font(.callout.weight(.semibold))
            Text(sentence).font(.callout)
            if let first = readiness.suggestions.first {
                if session.learner?.kind == .child {
                    Button { session.openStockLesson(first.pageID) } label: {
                        Label("Learn \(first.title) first", systemImage: "book.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))
                } else {
                    ForEach(Array(readiness.suggestions.enumerated()), id: \.element.pageID) { i, s in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Unit 1 · \(s.title)").font(.caption.weight(.semibold))
                                if let reason = s.reason { Text(reason.prefix(1).uppercased() + reason.dropFirst()).font(.caption2).foregroundColor(.secondary) }
                            }
                            Spacer()
                            if i == 0 {
                                Button("Open") { session.openStockLesson(s.pageID) }
                                    .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.compact))
                            }
                        }
                    }
                }
            }
            Button("Teach me this piece anyway") { session.beginTutoring(planLesson: true, ignoreReadiness: true) }
                .help("Plan the lesson now: the notes you haven't met become steps in it")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }

    private var sentence: String {
        let gaps = readiness.gaps
        let list = gaps.count <= 1 ? gaps.joined() : gaps.dropLast().joined(separator: ", ") + " and " + gaps.last!
        let n = readiness.suggestions.count
        return list.prefix(1).uppercased() + list.dropFirst() + ". "
            + (n == 1 ? "This lesson in Unit 1 covers it:" : "These \(n) short Unit 1 lessons cover it, in order:")
    }
}

/// Bars the learner marked for extra attention, and practising just those.
private struct MarkedBarsSection: View {
    @EnvironmentObject var session: PlaySession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("Bars to focus on").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            if session.markedBars.isEmpty {
                Text("Option-click a bar on the score to mark it for extra practice.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                // One chip per bar; click to unmark.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 4)], alignment: .leading, spacing: 4) {
                    ForEach(session.markedBars.sorted(), id: \.self) { bar in
                        Button { session.toggleMark(bar: bar) } label: {
                            Label("\(bar)", systemImage: "xmark").font(.caption.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.purple.opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                        .help("Unmark bar \(bar)")
                    }
                }
                Button {
                    session.practiseMarkedBars()
                } label: {
                    Label("Practise \(session.markedBars.count == 1 ? "this bar" : "these \(session.markedBars.count) bars")",
                          systemImage: "scope").frame(maxWidth: .infinity)
                }
                .help("Note by note, slowly, at full speed, then with the bars around them")
            }
            HStack {
                if session.phase == .graded && !session.mistakeMeasures.isEmpty
                    && !session.mistakeMeasures.isSubset(of: session.markedBars) {
                    Button("Mark the bars I got wrong") { session.markMistakeBars() }
                }
                if !session.markedBars.isEmpty {
                    Button("Clear") { session.clearMarks() }
                }
            }
            .font(.caption)
        }
    }
}

/// The lesson plan as a checklist: done, current and to do. Clicking a step goes there.
private struct PlanChecklist: View {
    @EnvironmentObject var session: PlaySession
    let engine: PiecePracticeEngine
    /// Called after a step is chosen, so the popover can close.
    var onChoose: () -> Void = {}

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lesson plan").font(.ppHeadline)
                    ForEach(Array(engine.steps.enumerated()), id: \.offset) { i, step in
                        row(i, step).id(i)
                    }
                }
                .padding(PP.Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 480)
            .frame(maxHeight: 560)
            .onAppear { if let i = engine.stepIndex { proxy.scrollTo(i, anchor: .center) } }
        }
    }

    private func row(_ i: Int, _ step: PracticeExercise) -> some View {
                Button {
                    session.tutorJump(to: i)
                    onChoose()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: icon(i))
                            .foregroundColor(engine.stepIndex == i ? .accentColor : engine.completedSteps.contains(i) ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.kind == .listen || step.kind == .newNote || step.kind == .perform ? step.title : "\(step.title) · \(step.whereText)")
                                .font(.system(size: 15))
                                .fontWeight(engine.stepIndex == i ? .semibold : .regular)
                                .fixedSize(horizontal: false, vertical: true)
                            if engine.stepIndex == i, let tip = tip(for: step) {
                                Text(tip).font(.system(size: 13)).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let why = step.skipReason, engine.stepIndex != i, !engine.completedSteps.contains(i) {
                                Text("Skipped: \(why.prefix(1).lowercased() + why.dropFirst())").font(.system(size: 13)).foregroundColor(.secondary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
    }

    private func icon(_ i: Int) -> String {
        engine.stepIndex == i ? "play.circle.fill" : engine.completedSteps.contains(i) ? "checkmark.circle.fill"
            : engine.skippedSteps.contains(i) ? "arrow.uturn.right.circle" : "circle"
    }

    private func tip(for step: PracticeExercise) -> String? {
        guard let plan = engine.plan, let label = step.label else { return nil }
        return plan.phrases.first { $0.label == label }?.tip
    }
}
#endif
