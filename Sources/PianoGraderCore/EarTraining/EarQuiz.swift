import Foundation

public struct EarResponse: Sendable, Equatable {
    public let answerID: String?
    public let isCorrect: Bool
}

public struct EarQuizResult: Sendable {
    public let stage: EarStageID
    public let correct: Int
    public let total: Int
    public let missed: [EarAnswer]
    public var shouldAdvance: Bool { total > 0 && Double(correct) / Double(total) >= 0.8 }
    public var recommendedStage: EarStageID { shouldAdvance ? stage.next ?? stage : stage }
}

/// Only Next advances the cursor. Submission is idempotent, including for skipped questions.
public struct EarQuiz: Sendable {
    public let questions: [EarQuestion]
    public private(set) var index = 0
    public private(set) var responses: [EarResponse] = []
    public var isFinished: Bool { !questions.isEmpty && index == questions.count }
    public var question: EarQuestion? { questions.indices.contains(index) ? questions[index] : nil }
    public var response: EarResponse? { responses.indices.contains(index) ? responses[index] : nil }

    public init(questions: [EarQuestion]) { self.questions = questions }

    @discardableResult
    public mutating func submit(answerID: String?) -> Bool {
        guard let q = question, response == nil,
              answerID == nil || q.choices.contains(where: { $0.id == answerID }) else { return false }
        responses.append(EarResponse(answerID: answerID, isCorrect: answerID == q.correctAnswer.id))
        return true
    }

    @discardableResult
    public mutating func next() -> Bool {
        guard question != nil, response != nil else { return false }
        index += 1
        return true
    }

    public var result: EarQuizResult? {
        guard isFinished, let stage = questions.first?.stage else { return nil }
        var seen = Set<String>()
        let missed = zip(questions, responses).compactMap { q, response -> EarAnswer? in
            !response.isCorrect && seen.insert(q.correctAnswer.id).inserted ? q.correctAnswer : nil
        }
        return EarQuizResult(stage: stage, correct: responses.filter(\.isCorrect).count,
                             total: questions.count, missed: missed)
    }
}

public struct EarStageProgress: Codable, Equatable, Sendable {
    /// Best score, out of 10 (a 5-question quiz counts double), so 8 always means mastered.
    public private(set) var bestCorrect: Int = 0
    public private(set) var completedQuizzes: Int = 0
    public init() {}
    mutating func record(_ result: EarQuizResult) {
        bestCorrect = max(bestCorrect, result.correct * 10 / result.total)
        completedQuizzes += 1
    }
}

public struct EarProgress: Codable, Equatable, Sendable {
    public private(set) var version = 1
    public private(set) var stages: [String: EarStageProgress] = [:]
    public private(set) var recommendedStage = EarStageID.first
    public init() {}

    public mutating func record(_ result: EarQuizResult) {
        guard [5, 10].contains(result.total), (0...result.total).contains(result.correct),
              EarCurriculum.stage(result.stage) != nil else { return }
        var stageProgress = stages[result.stage.id] ?? EarStageProgress()
        stageProgress.record(result)
        stages[result.stage.id] = stageProgress
        recommendedStage = result.recommendedStage
    }

    public static func decode(_ data: Data?) -> EarProgress {
        guard let data, let value = try? JSONDecoder().decode(EarProgress.self, from: data),
              value.version == 1, EarCurriculum.stage(value.recommendedStage) != nil,
              value.stages.allSatisfy({ key, progress in
                  EarCurriculum.levels.flatMap(\.stages).contains { $0.id.id == key }
                      && (0...10).contains(progress.bestCorrect) && progress.completedQuizzes >= 0
              }) else { return EarProgress() }
        return value
    }
}
