#if canImport(SwiftUI)
import SwiftUI
import PianoGraderCore

/// Just the exercise, inside a lesson's own navigation and progress chrome.
@MainActor public struct EarLessonQuizView: View {
    @ObservedObject var session: EarTrainingSession
    let passAccuracy: Double
    let onContinue: () -> Void
    public init(session: EarTrainingSession, passAccuracy: Double = 0.8, onContinue: @escaping () -> Void) {
        self.session = session; self.passAccuracy = passAccuracy; self.onContinue = onContinue
    }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = session.error ?? session.persistenceError {
                    Text(error).foregroundStyle(.red)
                    if session.hasUnsavedProgress { Button("Retry saving") { session.retrySave() } }
                }
                if let result = session.result {
                    Text("\(result.correct) / \(result.total)").font(.largeTitle.bold())
                    let passed = Double(result.correct) / Double(max(1, result.total)) >= passAccuracy
                    Text(passed ? "Well listened. Ready for the next step." : "Listen to the reference and try again. Aim for \(Int((passAccuracy * 100).rounded()))%.")
                    if !result.missed.isEmpty { Text("Revisit: " + result.missed.map(\.title).joined(separator: " · ")).foregroundStyle(.secondary) }
                    HStack {
                        Button("Try again") { session.startQuiz() }.earButton(.secondary)
                        if passed { Button("Continue", action: onContinue).earButton(.primary).keyboardShortcut(.defaultAction) }
                    }
                } else if let question = session.question, let quiz = session.quiz {
                    Text("Question \(quiz.index + 1) of \(quiz.questions.count)").font(.headline)
                    Text(question.prompt).font(.title2.bold())
                    Text(question.context).foregroundStyle(.secondary)
                    DisclosureGroup("Hear labeled examples") {
                        ForEach(session.examples) { example in
                            VStack(alignment: .leading) {
                                Button(example.solutionLabel.components(separatedBy: "\n")[0]) { session.playLessonExample(example) }
                                Text(example.explanation).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                    HStack {
                        Button(session.heardQuestion ? "Replay" : "Play") { session.playQuestion() }
                            .earButton(.primary).keyboardShortcut(.space, modifiers: [])
                        Button(question.referenceLabel) { session.playReference() }.earButton(.secondary)
                        if session.isPlaying { Button("Stop") { session.stop() }.earButton(.secondary) }
                    }
                    Text(session.isPlaying ? "Listening…" : session.heardQuestion ? "Choose an answer." : "Listen to the complete example before answering.")
                        .font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                        ForEach(Array(question.choices.enumerated()), id: \.element.id) { i, answer in
                            Button { session.answer(answer.id) } label: {
                                Text(answer.title)
                                    .font(question.stage.level <= 2 ? .system(size: 32, weight: .bold, design: .rounded) : .title3.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .padding(.horizontal, 8)
                            }
                                .earButton(.secondary).controlSize(.large)
                                .keyboardShortcut(KeyEquivalent(Array("1234567890-=")[i]), modifiers: [])
                                .disabled(!session.canAnswer)
                        }
                    }
                    if let response = quiz.response {
                        Label(response.isCorrect ? "Correct" : "Answer: \(question.correctAnswer.title)",
                              systemImage: response.isCorrect ? "checkmark.circle.fill" : "info.circle")
                        Text(question.explanation)
                        Button("Hear the solution") { session.playSolution() }.earButton(.secondary)
                        Button(quiz.index + 1 == quiz.questions.count ? "See results" : "Next") { session.next() }
                            .earButton(.primary).keyboardShortcut(.defaultAction)
                    } else { Button("Skip question") { session.skip() }.earButton(.secondary) }
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.onDisappear { session.stop() }
    }
}
#endif
