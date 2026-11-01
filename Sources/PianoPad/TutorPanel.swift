#if os(macOS)
import SwiftUI
import PianoLessons
import PianoPadState

struct TutorPanel: View {
    @EnvironmentObject var session: PlaySession
    @State private var settings = false
    /// Start the tutor's next step by itself after a short countdown (hover pauses it).
    @AppStorage("PianoPad.tutor.autoContinue") private var autoContinue = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Piece tutor").font(.headline); Spacer(); Button("AI settings") { settings = true } }
            if let engine = session.tutor {
                Text(session.tutorAI.isEmpty ? session.tutorText : session.tutorAI)
                if session.tutorBusy { ProgressView("Preparing explanation…") }
                if let note = session.tutorNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                if session.tutorPlanning {
                    ProgressView(session.tutorPlanNote ?? "Planning your lesson…")
                    Button("Use a quick plan instead") { session.useQuickTutorPlan() }
                        .help("Plan the lesson in code now, without waiting for Muse Spark")
                } else {
                    if !engine.steps.isEmpty { PlanChecklist(engine: engine) }
                    current(engine)
                }
                Button("End tutoring") { session.endTutoring() }
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
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Start the lesson over") { session.beginTutoring(planLesson: true, startOver: true) }
                        .help("Same plan, from the first step; your progress on it is forgotten")
                } else {
                    Button("Teach me this piece") { session.beginTutoring(planLesson: true) }
                        .help("Plan a lesson for this piece: listen, new notes, phrase by phrase, then perform")
                }
            }
        }.sheet(isPresented: $settings) { AISettingsView { settings = false } }
    }

    @ViewBuilder private func current(_ engine: PiecePracticeEngine) -> some View {
        let e = engine.exercise
        Text("\(e.title) · \(e.whereText)\(e.isTimed ? " · \(Int(e.tempoPercent))%" : "")").font(.callout.weight(.semibold))
        if let stars = engine.lastStars {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < stars ? "star.fill" : "star").foregroundColor(.yellow)
                }
                Text(engine.mastered ? "Piece passed" : "Last performance").font(.caption).padding(.leading, 4)
            }
        }
        if e.isTimed || e.isWaitMode {
            Text("Clean runs: \(engine.cleanStreak)/\(engine.needed)").font(.caption)
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
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.phase == .recording)
        }
        Toggle("Start the next step by itself", isOn: $autoContinue)
            .font(.caption)
            .help("After each step, the next one starts after a short countdown. Hover over the button to pause it.")
        HStack {
            Button("Hear it first") { session.startListening() }
            Button("Try again") { session.retryTutorExercise() }
            Button("Skip step") { session.tutor?.skip() }
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
                Button("Reassess piece") { session.tutor?.reassess(); session.startTutorExercise() }
            }
            Menu("More") {
                if !engine.steps.isEmpty {
                    Button("Back to the lesson plan") { session.tutorJump(to: 0) }
                }
                Button("Learn whole piece note by note") { session.tutor?.learnNotes(); session.startTutorExercise() }
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
        autoContinue && !engine.mastered && !session.isAuditioning && !session.tutorBusy && !session.tutorPlanning
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
        case .placement: return "Play the whole piece once, as well as you can. Parts you play cleanly are ticked off. Not ready? Skip step."
        default: return "Ready when you are: press \(startLabel(e)), then play after the count-in\(e.hand == nil ? "" : " (\(e.hand == .left ? "left" : "right") hand only)")."
        }
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
                        Label("Learn \(first.title) first", systemImage: "book.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
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
                                    .buttonStyle(.borderedProminent).controlSize(.small)
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

/// The lesson plan as a checklist: done, current and to do. Clicking a step goes there.
private struct PlanChecklist: View {
    @EnvironmentObject var session: PlaySession
    let engine: PiecePracticeEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Lesson plan").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            ForEach(Array(engine.steps.enumerated()), id: \.offset) { i, step in
                Button {
                    session.tutorJump(to: i)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: icon(i))
                            .foregroundColor(engine.stepIndex == i ? .accentColor : engine.completedSteps.contains(i) ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.kind == .listen || step.kind == .newNote || step.kind == .perform ? step.title : "\(step.title) · \(step.whereText)")
                                .font(.caption)
                                .fontWeight(engine.stepIndex == i ? .semibold : .regular)
                            if engine.stepIndex == i, let tip = tip(for: step) {
                                Text(tip).font(.caption2).foregroundColor(.secondary)
                            }
                            if let why = step.skipReason, engine.stepIndex != i, !engine.completedSteps.contains(i) {
                                Text("Skipped: \(why.prefix(1).lowercased() + why.dropFirst())").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(session.phase == .recording)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
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
