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
    public var examples: [EarQuestion] { EarQuestionGenerator.examples(stage: selectedStage) }

    public func select(_ stage: EarStageID) {
        guard EarCurriculum.stage(stage) != nil else { return }
        stop()
        selectedStage = stage
        screen = .overview
        quiz = nil
        heardQuestion = false
    }

    public func learn() { stop(); screen = .learning; quiz = nil }
    public func overview() { stop(); screen = .overview; quiz = nil }

    public func startQuiz(seed: UInt64 = UInt64.random(in: .min ... .max)) {
        stop()
        quiz = EarQuiz(questions: EarQuestionGenerator.quiz(stage: selectedStage, seed: seed))
        heardQuestion = false
        screen = .quiz
    }

    public func playQuestion() {
        guard screen == .quiz, let question else { return }
        play(question.stimulus, marksQuestionHeard: true)
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
        if quiz?.submit(answerID: id) == true { onActivity?(.answer) }
    }

    public func skip() {
        guard screen == .quiz, quiz?.response == nil else { return }
        stop()
        if quiz?.submit(answerID: nil) == true { onActivity?(.skip) }
    }

    public func next() {
        guard screen == .quiz, quiz?.response != nil else { return }
        stop()
        quiz?.next()
        heardQuestion = false
        if let result = quiz?.result {
            progress.record(result)
            retrySave()
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
#endif
