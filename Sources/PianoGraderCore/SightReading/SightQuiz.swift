import Foundation

public struct SightResponse: Sendable, Equatable {
    /// The choice made, or nil when skipped or answered at the keys.
    public let answerID: String?
    /// The key played, when answered at the keys.
    public let playedPitch: Int?
    public let isCorrect: Bool
}

public struct SightQuizResult: Sendable, Equatable {
    public let stage: SightStageID
    public let correct: Int
    public let total: Int
    /// Answers got wrong, each once.
    public let missed: [SightAnswer]
    public var accuracy: Double { Double(correct) / Double(max(1, total)) }
}

/// A run of questions. Only `next()` moves on; answering twice does nothing.
public struct SightQuiz: Sendable {
    public let questions: [SightQuestion]
    public private(set) var index = 0
    public private(set) var responses: [SightResponse] = []
    public var isFinished: Bool { !questions.isEmpty && index == questions.count }
    public var question: SightQuestion? { questions.indices.contains(index) ? questions[index] : nil }
    public var response: SightResponse? { responses.indices.contains(index) ? responses[index] : nil }

    public init(questions: [SightQuestion]) { self.questions = questions }

    /// A choice, or nil to skip (counts as wrong).
    @discardableResult
    public mutating func submit(answerID: String?) -> Bool {
        guard let q = question, response == nil,
              answerID == nil || q.choices.contains(where: { $0.id == answerID }) else { return false }
        responses.append(SightResponse(answerID: answerID, playedPitch: nil, isCorrect: answerID == q.correctAnswer.id))
        return true
    }

    /// A key played. Only note-name questions take one, and only the exact key is right.
    @discardableResult
    public mutating func submit(playedPitch: Int) -> Bool {
        guard let q = question, let target = q.playPitch, response == nil else { return false }
        responses.append(SightResponse(answerID: nil, playedPitch: playedPitch, isCorrect: playedPitch == target))
        return true
    }

    @discardableResult
    public mutating func next() -> Bool {
        guard question != nil, response != nil else { return false }
        index += 1
        return true
    }

    public var result: SightQuizResult? {
        guard isFinished, let stage = questions.first?.stage else { return nil }
        var seen = Set<String>()
        let missed = zip(questions, responses).compactMap { q, response -> SightAnswer? in
            !response.isCorrect && seen.insert(q.correctAnswer.id).inserted ? q.correctAnswer : nil
        }
        return SightQuizResult(stage: stage, correct: responses.filter(\.isCorrect).count, total: questions.count, missed: missed)
    }
}
