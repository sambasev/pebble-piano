#if os(macOS)
import PianoGraderCore
import PianoLessons
import SwiftUI

/// A sight-reading quiz under way on a lesson page. The runner starts it and feeds it the
/// keys played; the view answers it with buttons.
final class SightReadingSession: ObservableObject {
    @Published private(set) var quiz: SightQuiz?
    @Published private(set) var examples: [SightQuestion] = []
    private(set) var config: Block.SightReading?
    /// An answer went in: right or wrong.
    var onAnswered: ((Bool) -> Void)?
    var onFinished: ((SightQuizResult) -> Void)?
    /// A right answer moves on by itself after this long; a wrong one waits for Next,
    /// so the explanation can be read.
    static let advanceDelay = 1.0
    private var pendingAdvance: DispatchWorkItem?

    var question: SightQuestion? { quiz?.question }
    var result: SightQuizResult? { quiz?.result }
    var canAnswer: Bool { quiz?.question != nil && quiz?.response == nil }

    func start(_ config: Block.SightReading) {
        cancelAdvance()
        self.config = config
        examples = SightQuestionGenerator.examples(stage: config.stageID)
        quiz = SightQuiz(questions: SightQuestionGenerator.quiz(stage: config.stageID, seed: .random(in: 0...UInt64.max),
                                                                count: config.questions))
    }

    func restart() {
        if let config { start(config) }
    }

    func stop() {
        cancelAdvance()
        quiz = nil
        config = nil
        onAnswered = nil
        onFinished = nil
    }

    func answer(_ id: String?) {
        guard quiz?.submit(answerID: id) == true else { return }
        answered()
    }

    /// A key played: answers a note-name question. False when the question doesn't take one.
    @discardableResult
    func play(_ pitch: Int) -> Bool {
        guard quiz?.submit(playedPitch: pitch) == true else { return false }
        answered()
        return true
    }

    func next() {
        cancelAdvance()
        guard quiz?.next() == true else { return }
        if let result { onFinished?(result) }
    }

    private func answered() {
        let correct = quiz?.response?.isCorrect ?? false
        onAnswered?(correct)
        guard correct, let index = quiz?.index else { return }
        cancelAdvance()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.quiz?.index == index, self.quiz?.response != nil else { return }
            self.next()
        }
        pendingAdvance = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.advanceDelay, execute: work)
    }

    private func cancelAdvance() {
        pendingAdvance?.cancel()
        pendingAdvance = nil
    }
}

/// The quiz: the staff to read, the choices, then what it was and why.
struct SightReadingQuizView: View {
    @ObservedObject var session: SightReadingSession
    let passAccuracy: Double
    let onContinue: () -> Void
    @State private var showExamples = true
    /// A short window (a small laptop): a smaller staff and buttons, so the choices fit
    /// above the keyboard without scrolling.
    @Environment(\.ppCompact) private var compact

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compact ? PP.Space.s3 : PP.Space.s4) {
                if let result = session.result {
                    results(result)
                } else if let question = session.question, let quiz = session.quiz {
                    HStack(alignment: .top, spacing: PP.Space.s6) {
                        VStack(alignment: .leading, spacing: compact ? PP.Space.s2 : PP.Space.s3) {
                            Text("Question \(quiz.index + 1) of \(quiz.questions.count)").ppEyebrow()
                            Text(question.prompt).font(.ppHeadline)
                            SightStaffView(score: question.score, spacing: compact ? 10 : 14, mark: mark(quiz.response))
                        }
                        Spacer(minLength: 0)
                        if quiz.response != nil { feedback(question, quiz: quiz) }
                    }
                    choices(question)
                    DisclosureGroup(isExpanded: $showExamples) {
                        examples
                    } label: {
                        Text("Examples").font(.ppCallout).foregroundColor(PP.inkMuted)
                    }
                }
            }
            .padding(compact ? PP.Space.s3 : PP.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundColor(PP.ink)
    }

    private func mark(_ response: SightResponse?) -> InkColor? {
        response.map { $0.isCorrect ? .played : .wrong }
    }

    private func choices(_ question: SightQuestion) -> some View {
        let columns = [GridItem(.adaptive(minimum: question.choices.count > 4 ? 72 : 150), spacing: PP.Space.s3)]
        let response = session.quiz?.response
        return LazyVGrid(columns: columns, alignment: .leading, spacing: PP.Space.s3) {
            ForEach(Array(question.choices.enumerated()), id: \.element.id) { i, answer in
                let chosen = response?.answerID == answer.id
                let isAnswer = response != nil && answer.id == question.correctAnswer.id
                Button { session.answer(answer.id) } label: {
                    Text(answer.title)
                        .font(answer.title.count <= 2 ? .system(size: 26, weight: .bold, design: .rounded) : .ppButton)
                        .frame(maxWidth: .infinity, minHeight: compact ? 42 : 52)
                        .background(RoundedRectangle(cornerRadius: PP.Radius.md)
                            .fill(isAnswer ? PP.success.opacity(0.18) : chosen ? PP.mistake.opacity(0.15) : PP.surfaceGlass))
                        .overlay(RoundedRectangle(cornerRadius: PP.Radius.md)
                            .strokeBorder(isAnswer ? PP.success : chosen ? PP.mistake : PP.inkStaff.opacity(0.45), lineWidth: isAnswer || chosen ? 2 : 1))
                        .contentShape(RoundedRectangle(cornerRadius: PP.Radius.md))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Array("1234567890")[min(i, 9)]), modifiers: .command)
                .disabled(!session.canAnswer)
            }
        }
    }

    private func feedback(_ question: SightQuestion, quiz: SightQuiz) -> some View {
        let response = quiz.response!
        let played = response.playedPitch.map { NoteName(pitch: $0).name }
        return VStack(alignment: .leading, spacing: PP.Space.s2) {
            Label(response.isCorrect ? "Correct" : "It's \(question.correctAnswer.title)",
                  systemImage: response.isCorrect ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.ppHeadline)
                .foregroundColor(response.isCorrect ? PP.success : PP.mistake)
            if let played, !response.isCorrect, let target = question.playPitch {
                Text("You played \(played); this is \(NoteName(pitch: target).name).").font(.ppCallout)
            }
            Text(question.explanation).font(.ppCallout).foregroundColor(PP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button(quiz.index + 1 == quiz.questions.count ? "See results" : "Next") { session.next() }
                .buttonStyle(PPPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private var examples: some View {
        let columns = [GridItem(.adaptive(minimum: 130), spacing: PP.Space.s3)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: PP.Space.s3) {
            ForEach(session.examples) { example in
                VStack(alignment: .leading, spacing: PP.Space.s1) {
                    SightStaffView(score: example.score, spacing: 8)
                    Text(example.playPitch.map { NoteName(pitch: $0).name } ?? example.correctAnswer.title)
                        .font(.ppCaption).foregroundColor(PP.inkMuted)
                }
            }
        }
        .padding(.top, PP.Space.s2)
    }

    private func results(_ result: SightQuizResult) -> some View {
        let passed = result.accuracy >= passAccuracy
        return VStack(alignment: .leading, spacing: PP.Space.s3) {
            Text("\(result.correct) / \(result.total)").font(.ppDisplay)
            Text(passed ? "Well read. Ready for the next step."
                        : "Look at the examples and try again. Aim for \(Int((passAccuracy * 100).rounded()))%.")
                .font(.ppHeadline)
            if !result.missed.isEmpty {
                Text("Look again at: " + result.missed.map(\.title).joined(separator: " · "))
                    .font(.ppCallout).foregroundColor(PP.inkMuted)
            }
            HStack(spacing: PP.Space.s3) {
                Button("Try again") { session.restart() }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                if passed {
                    Button("Continue", action: onContinue)
                        .buttonStyle(PPPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

/// One staff with its clef and symbol, on paper. `mark` recolours the symbol (green right,
/// red wrong) once answered.
struct SightStaffView: View {
    let score: Score
    var spacing: Double = 12
    var mark: InkColor? = nil
    @Environment(\.paper) private var paper

    var body: some View {
        var metrics = ScoreLayout.Metrics(spacing: spacing)
        metrics.timeSignature = false
        metrics.systemMargin = 3.5
        let layout = ScoreLayout(score: score, width: 13 * spacing, metrics: metrics)
        let items = ScoreRenderer(layout: layout).renderScore().items.map { item -> DrawItem in
            guard let mark, case let .glyph(glyph, at, size, _) = item, glyph != .gClef, glyph != .fClef else { return item }
            return .glyph(glyph, at: at, size: size, color: mark)
        }
        return Canvas { context, _ in
            DrawingPainter.paint(items, paper: paper, in: &context)
        }
        .frame(width: layout.width, height: layout.height)
        .padding(.horizontal, spacing)
        .ppPaper()
        .accessibilityHidden(true)
    }
}
#endif
