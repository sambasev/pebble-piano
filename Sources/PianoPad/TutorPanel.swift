#if os(macOS)
import SwiftUI
import PianoLessons

struct TutorPanel: View {
    @EnvironmentObject var session: PlaySession
    @State private var settings = false
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
            } else if session.reference?.notes.isEmpty == false {
                Button("Teach me this piece") { session.beginTutoring(planLesson: true) }
                    .help("Plan a lesson for this piece: listen, new notes, phrase by phrase, then perform")
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
        Button {
            session.startTutorExercise()
        } label: {
            Label(startLabel(e), systemImage: e.kind == .listen ? "speaker.wave.2.fill" : "play.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(session.phase == .recording)
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

    private func startLabel(_ e: PracticeExercise) -> String {
        switch e.kind {
        case .assessment: return "Start assessment"
        case .listen: return "Listen"
        case .newNote: return "Find the note"
        case .perform: return "Perform"
        default: return "Start step"
        }
    }

    private func readyText(_ e: PracticeExercise) -> String {
        switch e.kind {
        case .listen: return "Press Listen and follow the music."
        case .newNote: return "Press Find the note, then play the highlighted key."
        case .notes: return "Press Start step: the music waits for each note\(e.hand == nil ? "" : "—play only the \(e.hand == .left ? "left" : "right") hand")."
        case .perform: return "Press Perform, then play the whole piece after the count-in."
        default: return "Ready when you are: press \(startLabel(e)), then play after the count-in\(e.hand == nil ? "" : " (\(e.hand == .left ? "left" : "right") hand only)")."
        }
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
        engine.stepIndex == i ? "play.circle.fill" : engine.completedSteps.contains(i) ? "checkmark.circle.fill" : "circle"
    }

    private func tip(for step: PracticeExercise) -> String? {
        guard let plan = engine.plan, let label = step.label else { return nil }
        return plan.phrases.first { $0.label == label }?.tip
    }
}
#endif
