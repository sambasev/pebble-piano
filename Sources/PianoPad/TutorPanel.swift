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
                Text("\(engine.exercise.title) · bars \(engine.exercise.measures.lowerBound)–\(engine.exercise.measures.upperBound) · \(Int(engine.exercise.tempoPercent))%")
                Text("Clean runs: \(engine.cleanStreak)/\(engine.needed)").font(.caption)
                if session.tutorAttempt == nil {
                    Text("Ready when you are. Click Start assessment below, then play after the count-in.")
                        .font(.callout)
                }
                Button {
                    session.startTutorExercise()
                } label: {
                    Label(engine.exercise.kind == .assessment ? "Start assessment" : "Start exercise", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.phase == .recording)
                HStack {
                    Button("Hear it first") { session.startListening() }
                    Button("Learn note by note") { session.tutor?.learnNotes(); session.startTutorExercise() }
                }
                HStack {
                    Button("Try again") { session.retryTutorExercise() }
                    Button("Reassess piece") { session.tutor?.reassess(); session.startTutorExercise() }
                }
                Button("Move on from exercise") { session.tutor?.skip() }
                HStack {
                    Button("What went wrong?") { session.askTutor("What went wrong?", userAsked: true) }
                    Button("Why this exercise?") { session.askTutor("Why this exercise?", userAsked: true) }
                }.disabled(session.phase == .recording)
                Button("End tutoring") { session.endTutoring() }
            } else if session.reference?.notes.isEmpty == false {
                Button("Teach me this piece") { session.beginTutoring() }
            }
        }.sheet(isPresented: $settings) { AISettingsView { settings = false } }
    }
}
#endif
