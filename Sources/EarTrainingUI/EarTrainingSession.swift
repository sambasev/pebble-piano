#if canImport(Combine)
import Foundation
import Combine
import PianoGraderCore

@MainActor public protocol EarProgressStore {
    func load() -> EarProgress
    func save(_ progress: EarProgress) throws
}

@MainActor public final class EarLocalProgressStore: EarProgressStore {
    public static let key = "earTraining.progress.v1"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> EarProgress { EarProgress.decode(defaults.data(forKey: Self.key)) }
    public func save(_ progress: EarProgress) {
        if let data = try? JSONEncoder().encode(progress) { defaults.set(data, forKey: Self.key) }
    }
}
@MainActor public final class EarTrainingSession: ObservableObject {
    public enum Screen { case overview, learning, quiz, results }
    public enum Activity { case listening, answer, skip }
    public var onActivity: (@MainActor (Activity) -> Void)?
    public var onQuizCompleted: (@MainActor (EarQuizResult, String) -> Void)?
    @Published public private(set) var selectedStage: EarStageID
    @Published public private(set) var screen: Screen = .overview
    @Published public private(set) var progress: EarProgress
    @Published public private(set) var quiz: EarQuiz?
    @Published public private(set) var isPlaying = false
    @Published public private(set) var heardQuestion = false
    @Published public private(set) var error: String?
    @Published public private(set) var playingExampleID: String?
    @Published public private(set) var hasUnsavedProgress = false
    @Published public private(set) var persistenceError: String?
    private let playback: any EarPlayback
    private let store: any EarProgressStore
    private var playToken: UInt64 = 0
    private var lessonCount = 10
    private var lessonNotes: [Int]?
    /// Each new question plays by itself (reference first), and an answer moves on by itself.
    public var autoPlay = true
    private var advanceTask: Task<Void, Never>?
    /// Silence between the reference and the question.
    static let referenceGap = 0.45
    /// How long the answer stays on screen before the next question.
    static let advanceDelay = (correct: 1.0, wrong: 2.5)

    public func startLessonQuiz(stage: EarStageID, questions: Int, notes: [Int]? = nil) {
        select(stage)
        lessonCount = questions; lessonNotes = notes
        startQuiz()
    }

    public convenience init() {
        self.init(playback: EarPlaybackController(), store: EarLocalProgressStore())
    }

    public init(playback: any EarPlayback, store: any EarProgressStore) {
        self.playback = playback
        self.store = store
        let progress = store.load()
        self.progress = progress
        self.selectedStage = progress.recommendedStage
    }

    public var question: EarQuestion? { quiz?.question }
    public var canAnswer: Bool { screen == .quiz && heardQuestion && !isPlaying && quiz?.response == nil }
    public var result: EarQuizResult? { quiz?.result }
    public var examples: [EarQuestion] {
        EarQuestionGenerator.examples(stage: selectedStage).filter { example in
            lessonNotes.map { $0.contains(Int(example.correctAnswer.id.replacingOccurrences(of: "note.", with: "")) ?? -1) } ?? true
        }
    }

    public func playLessonExample(_ example: EarQuestion) {
        guard screen == .quiz, examples.contains(where: { $0.id == example.id }) else { return }
        play(example.solution)
    }

    public func select(_ stage: EarStageID) {
        guard EarCurriculum.stage(stage) != nil else { return }
        stop()
        selectedStage = stage
        lessonCount = 10; lessonNotes = nil
        screen = .overview
        quiz = nil
        heardQuestion = false
    }

    public func learn() { stop(); screen = .learning; quiz = nil }
    public func overview() { stop(); screen = .overview; quiz = nil }

    public func startQuiz(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        stop()
        quiz = EarQuiz(questions: EarQuestionGenerator.quiz(stage: selectedStage, seed: seed, count: lessonCount, notes: lessonNotes))
        heardQuestion = false
        screen = .quiz
        if autoPlay { playQuestion() }
    }

    /// The reference (C4 for notes, the root or tonic otherwise), a short gap, then the question.
    public func playQuestion() {
        guard screen == .quiz, let question else { return }
        let start = (question.reference.map(\.offset).max() ?? 0) + Self.referenceGap
        let stimulus = question.stimulus.map { note -> NoteEvent in
            var n = note
            n.onset += start
            n.offset += start
            return n
        }
        play(question.reference + stimulus, marksQuestionHeard: true)
    }

    public func playReference() {
        guard let question else { return }
        play(question.reference)
    }

    public func playSolution() {
        guard let question, quiz?.response != nil else { return }
        play(question.solution)
    }

    public func playExample(_ example: EarQuestion, reference: Bool = false) {
        guard screen == .learning else { return }
        play(reference ? example.reference : example.solution, exampleID: example.id)
    }

    public func answer(_ id: String) {
        guard canAnswer else { return }
        if quiz?.submit(answerID: id) == true {
            onActivity?(.answer)
            advanceSoon(correct: quiz?.response?.isCorrect == true)
        }
    }

    public func skip() {
        guard screen == .quiz, quiz?.response == nil else { return }
        stop()
        if quiz?.submit(answerID: nil) == true {
            onActivity?(.skip)
            advanceSoon(correct: false)
        }
    }

    /// Moves to the next question once the answer has been seen. Playing anything first
    /// (Hear the solution, Replay) cancels it, and Next still works straight away.
    private func advanceSoon(correct: Bool) {
        guard autoPlay, let index = quiz?.index else { return }
        let delay = correct ? Self.advanceDelay.correct : Self.advanceDelay.wrong
        advanceTask?.cancel()
        advanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, self.screen == .quiz,
                  self.quiz?.index == index, self.quiz?.response != nil else { return }
            self.next()
        }
    }

    public func next() {
        guard screen == .quiz, quiz?.response != nil else { return }
        stop()
        quiz?.next()
        heardQuestion = false
        if quiz?.result == nil, autoPlay { playQuestion() }
        if let result = quiz?.result {
            // Course quizzes (any length) count toward progress; piano-page checks on a few notes don't.
            if lessonNotes == nil {
                progress.record(result)
                retrySave()
            }
            screen = .results
            onQuizCompleted?(result, quiz?.questions.first?.id ?? UUID().uuidString)
        }
    }

    public func retrySave() {
        do {
            try store.save(progress)
            hasUnsavedProgress = false
            persistenceError = nil
        } catch {
            hasUnsavedProgress = true
            persistenceError = "Couldn't save ear-training progress: \(error.localizedDescription). Retry saving before changing learners."
        }
    }

    public func stop() {
        advanceTask?.cancel()
        advanceTask = nil
        playToken &+= 1
        playback.stop()
        isPlaying = false
        playingExampleID = nil
        error = nil
    }

    private func play(_ notes: [NoteEvent], marksQuestionHeard: Bool = false, exampleID: String? = nil) {
        stop()
        isPlaying = true
        playingExampleID = exampleID
        let token = playToken
        playback.play(notes) { [weak self] result in
            guard let self, token == self.playToken else { return }
            self.isPlaying = false
            self.playingExampleID = nil
            switch result {
            case .success:
                if marksQuestionHeard { self.heardQuestion = true }
            case .failure(let error): self.error = error.localizedDescription
            }
        }
        if error == nil { onActivity?(.listening) }
    }
}

public extension EarQuestion {
    /// What plays, in order, for the line under the Play buttons.
    var listenOrder: String {
        "First the \(referenceLabel), then the \(stage.level <= 2 ? "note to name" : "question")."
    }
}
#endif
