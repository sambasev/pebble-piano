#if canImport(SwiftUI)
import SwiftUI
import PianoGraderCore

/// Embed this view in a future PianoPad tab. Disappearance cancels playback but retains quiz state.
@MainActor public struct EarTrainingView: View {
    @StateObject private var session: EarTrainingSession
    private let appearance: EarTrainingAppearance
    private var accent: Color { appearance.accent }

    public init(session: EarTrainingSession, appearance: EarTrainingAppearance = EarTrainingAppearance()) {
        _session = StateObject(wrappedValue: session)
        self.appearance = appearance
    }
    public init() {
        _session = StateObject(wrappedValue: EarTrainingSession())
        appearance = EarTrainingAppearance()
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 245)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    stages
                    if let error = session.error ?? session.persistenceError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.callout)
                            .padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Training error. \(error)")
                        if session.hasUnsavedProgress {
                            Button("Retry saving") { session.retrySave() }
                        }
                    }
                    switch session.screen {
                    case .overview: overview
                    case .learning: learning
                    case .quiz: quiz
                    case .results: results
                    }
                }
                .padding(30)
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(appearance.background)
        }
        .foregroundStyle(appearance.ink)
        .buttonBorderShape(.roundedRectangle)
        .tint(accent)
        .onDisappear { session.stop() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "ear.badge.waveform").font(.title).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appearance.embedded ? "Ear Training" : "EarTrainer").font(.headline)
                    if !appearance.embedded {
                        Text("Listen. Recognize. Grow.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(.horizontal, 18).padding(.top, 26)
            Divider()
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(EarCurriculum.levels) { level in
                        Button { session.select(level.stages[0].id) } label: {
                            HStack(spacing: 12) {
                                Text(String(level.id)).font(.system(.callout, design: .rounded).bold())
                                    .frame(width: 30, height: 30)
                                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(level.title).font(.callout.weight(.medium))
                                    Text(levelProgress(level)).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if level.id == session.selectedStage.level {
                                    Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(accent)
                                }
                            }
                            .padding(10)
                            .foregroundStyle(.primary)
                            .background(level.id == session.selectedStage.level ? accent.opacity(0.09) : .clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Level \(level.id), \(level.title), \(levelProgress(level))")
                    }
                }.padding(.horizontal, 10)
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("Your next step", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(accent)
                Button {
                    session.select(session.progress.recommendedStage)
                } label: {
                    Text(stageLabel(session.progress.recommendedStage)).font(.caption).multilineTextAlignment(.leading)
                }.buttonStyle(.plain)
                Text(appearance.embedded ? "Every level is open. Progress belongs to the current learner." : "Every level is open. Progress stays on this Mac.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(18)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LEVEL \(session.selectedStage.level) OF 8")
                    .font(.caption.weight(.bold)).tracking(2).foregroundStyle(accent)
                Spacer()
                if session.screen != .overview {
                    Button("Overview") { session.overview() }.buttonStyle(.borderless)
                }
            }
            Text(level.title).font(appearance.displayFont)
            Text(level.detail).font(.body).foregroundStyle(.secondary)
        }
    }

    private var stages: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(level.stages) { stage in
                Button { session.select(stage.id) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("STAGE \(stage.id.stage)").font(.caption2.weight(.bold))
                            Spacer()
                            if session.progress.stages[stage.id.id]?.bestCorrect ?? 0 >= 8 {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        Text(stage.title).font(.callout.weight(.semibold)).multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(stage.id == session.selectedStage ? accent : .primary)
                    .padding(14).frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                    .background(stage.id == session.selectedStage ? accent.opacity(0.1) : Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(stage.id == session.selectedStage ? accent.opacity(0.4) : .clear))
                }.buttonStyle(.plain)
                .accessibilityLabel("Stage \(stage.id.stage), \(stage.title)")
                .accessibilityAddTraits(stage.id == session.selectedStage ? .isSelected : [])
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 24) {
                Image(systemName: session.selectedStage.level < 3 ? "music.note" : "waveform")
                    .font(.system(size: 48, weight: .light)).foregroundStyle(accent)
                    .frame(width: 100, height: 110)
                    .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                VStack(alignment: .leading, spacing: 12) {
                    Text(stage.title).font(appearance.titleFont)
                    Text(stage.detail).foregroundStyle(.secondary)
                    HStack(spacing: 18) {
                        Label("10 questions", systemImage: "list.number")
                        Label("Unlimited replay", systemImage: "arrow.counterclockwise")
                    }.font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
            Divider()
            Text("Listen to a sound, then choose its name. Use the reference whenever you need it. You’ll see the answer and an explanation after each question.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button { session.startQuiz() } label: { Label("Start Quiz", systemImage: "play.fill") }
                    .earButton(.primary).controlSize(.large)
                Button { session.learn() } label: { Label("Learn the sounds", systemImage: "book") }
                    .earButton(.secondary).controlSize(.large)
            }
            if let progress = session.progress.stages[stage.id.id] {
                Label("Best: \(progress.bestCorrect)/10 · \(progress.completedQuizzes) completed quizzes", systemImage: "chart.bar.fill")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Score 8/10 to earn a recommendation for the next stage.").font(.caption).foregroundStyle(.secondary)
            }
        }.card(appearance)
    }

    private var learning: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Meet the sounds").font(appearance.titleFont)
                    Text("Labeled examples in C. Listen and compare; no score is recorded.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Start Quiz") { session.startQuiz() }.earButton(.primary)
            }
            ForEach(session.examples) { example in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(example.correctAnswer.title).font(.headline)
                        Spacer()
                        if session.playingExampleID == example.id { Image(systemName: "speaker.wave.2.fill").foregroundStyle(accent) }
                        Button { session.playExample(example) } label: { Label("Listen", systemImage: "play.fill") }
                        Button("Reference") { session.playExample(example, reference: true) }
                    }
                    Text(example.context).font(.caption).foregroundStyle(accent)
                    Text(example.explanation).font(.callout).foregroundStyle(.secondary)
                    Text(example.solutionLabel).font(.caption.monospaced()).foregroundStyle(.secondary)
                }.card(appearance)
            }
            if session.isPlaying { Button("Stop audio") { session.stop() } }
        }
    }

    @ViewBuilder private var quiz: some View {
        if let question = session.question, let quiz = session.quiz {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Question \(quiz.index + 1) of \(quiz.questions.count)").font(.callout.weight(.semibold))
                    Spacer()
                    Text("\(quiz.responses.filter(\.isCorrect).count) correct").font(.callout).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(quiz.index), total: Double(quiz.questions.count))
                VStack(alignment: .leading, spacing: 10) {
                    Text(question.prompt).font(appearance.titleFont)
                    Text(question.context).font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button { session.playQuestion() } label: {
                        Label(session.heardQuestion ? "Replay" : "Play", systemImage: "play.fill")
                    }
                    .earButton(.primary).controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [])
                    Button(question.referenceLabel) { session.playReference() }
                        .earButton(.secondary).controlSize(.large)
                    if session.isPlaying {
                        Button { session.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                            .buttonStyle(.borderless)
                    }
                }
                Text(session.isPlaying ? "Listening… \(question.listenOrder)" : session.heardQuestion ? "Choose your answer. Replay as often as you like." : "Press Play to listen. \(question.listenOrder)")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(Array(question.choices.enumerated()), id: \.element.id) { index, answer in
                        answerButton(answer, index: index, question: question)
                    }
                }
                if let response = quiz.response {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(response.isCorrect ? "Correct" : response.answerID == nil ? "Skipped" : "Keep listening",
                              systemImage: response.isCorrect ? "checkmark.circle.fill" : "info.circle.fill")
                            .font(.headline).foregroundStyle(response.isCorrect ? .green : accent)
                        Text("Answer: \(question.correctAnswer.title)").font(.headline)
                        Text(question.explanation).font(.callout)
                        Text(question.solutionLabel).font(.caption.monospaced()).foregroundStyle(.secondary)
                        HStack {
                            Button { session.playSolution() } label: { Label("Hear the solution", systemImage: "speaker.wave.2") }
                            Spacer()
                            Button(quiz.index == quiz.questions.count - 1 ? "See Results" : "Next") { session.next() }
                                .earButton(.primary).keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(18)
                    .background((response.isCorrect ? Color.green : accent).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    HStack {
                        Text("Shortcuts: 1–9, 0, −, = · Space to replay").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button("Skip") { session.skip() }.buttonStyle(.borderless)
                    }
                }
            }.card(appearance)
        }
    }

    private func answerButton(_ answer: EarAnswer, index: Int, question: EarQuestion) -> some View {
        let response = session.quiz?.response
        let correct = response != nil && answer.id == question.correctAnswer.id
        let wrong = response != nil && response?.answerID == answer.id && !correct
        let color = correct ? Color.green : wrong ? .red : accent
        return Button { session.answer(answer.id) } label: {
            HStack(spacing: 10) {
                Text(shortcutLabel(index)).font(.caption.monospaced().bold())
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                Text(answer.title)
                    .font(question.stage.level <= 2 ? .system(size: 32, weight: .bold, design: .rounded) : .callout.weight(.medium))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if correct { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                if wrong { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
            }
            .foregroundStyle(response != nil || session.canAnswer ? Color.primary : Color.secondary)
            .padding(12).frame(maxWidth: .infinity, minHeight: 58)
            .background(color.opacity(correct || wrong ? 0.1 : 0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(correct || wrong ? 0.5 : 0.15)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!session.canAnswer)
        .keyboardShortcut(KeyEquivalent(Character(shortcutLabel(index))), modifiers: [])
        .accessibilityLabel("\(answer.title)\(correct ? ", correct answer" : wrong ? ", your incorrect answer" : "")")
    }

    @ViewBuilder private var results: some View {
        if let result = session.result {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 20) {
                    Image(systemName: result.shouldAdvance ? "checkmark.seal.fill" : "ear.badge.waveform")
                        .font(.system(size: 52)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(result.correct) / \(result.total)").font(.system(size: 42, weight: .bold, design: .rounded))
                        Text(result.shouldAdvance ? "Strong listening. Keep growing." : "Every listen builds your ear.")
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                if !result.missed.isEmpty {
                    Text("Revisit these sounds").font(.headline)
                    Text(result.missed.map(\.title).joined(separator: " · ")).foregroundStyle(.secondary)
                }
                Text(result.shouldAdvance && result.stage.next == nil
                     ? "You completed the final stage. Repeat it for new roots and voicings."
                     : "Suggested next step: \(stageLabel(result.recommendedStage))")
                    .font(.callout)
                HStack(spacing: 12) {
                    Button("Retry with new sounds") { session.startQuiz() }.earButton(.primary)
                    if result.recommendedStage != result.stage {
                        Button("Next stage") { session.select(result.recommendedStage) }.earButton(.secondary)
                    }
                    Button("Review examples") { session.learn() }.earButton(.secondary)
                }
                Text("First answers only. Skips count as incorrect; replays and references are free.")
                    .font(.caption).foregroundStyle(.secondary)
            }.card(appearance)
        }
    }

    private var level: EarLevel { EarCurriculum.levels[session.selectedStage.level - 1] }
    private var stage: EarStage { EarCurriculum.stage(session.selectedStage)! }
    private func stageLabel(_ id: EarStageID) -> String {
        "Level \(id.level), stage \(id.stage) · \(EarCurriculum.stage(id)?.title ?? "")"
    }
    private func shortcutLabel(_ index: Int) -> String { ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="][index] }
    private func levelProgress(_ level: EarLevel) -> String {
        let completed = level.stages.filter { session.progress.stages[$0.id.id]?.bestCorrect ?? 0 >= 8 }.count
        return completed == 0 ? "3 stages · always open" : "\(completed) of 3 stages at 8/10+"
    }
}

private extension View {
    func card(_ appearance: EarTrainingAppearance) -> some View {
        padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(appearance.cardSurface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.07)))
    }
}
#endif
