import Foundation
import PianoGraderCore

public struct PracticeExercise: Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable { case assessment, notes, slow, fullSpeed, context }
    public var kind: Kind
    public var measures: ClosedRange<Int>
    public var tempoPercent: Double
    public var title: String { kind == .assessment ? "Play the whole piece" : kind == .notes ? "Learn note by note" : kind == .slow ? "Slowly, in time" : kind == .context ? "With surrounding bars" : "Full speed" }
    public init(kind: Kind, measures: ClosedRange<Int>, tempoPercent: Double = 100) {
        self.kind = kind; self.measures = measures; self.tempoPercent = tempoPercent
    }
    public func originalMeasure(_ local: Int) -> Int { measures.lowerBound + local - 1 }
    public func printedMeasure(_ local: Int, playOrder: [Int]) -> Int {
        let original = originalMeasure(local)
        return playOrder.indices.contains(original - 1) ? playOrder[original - 1] : original
    }
}

/// Decisions depend only on grading evidence. Language models never advance this engine.
public struct PiecePracticeEngine: Sendable {
    public let measureCount: Int
    public let persona: Persona
    public private(set) var exercise: PracticeExercise
    public private(set) var cleanStreak = 0
    public private(set) var runs = 0
    public private(set) var mastered = false
    private var queue: [PracticeExercise] = []
    public init(measureCount: Int, persona: Persona = .alex) {
        self.measureCount = max(1, measureCount); self.persona = persona
        exercise = PracticeExercise(kind: .assessment, measures: 1...max(1, measureCount))
    }
    public var needed: Int { exercise.kind == .notes ? 1 : persona.drill.cleanRunsNeeded }
    public mutating func reassess() {
        queue = []; cleanStreak = 0; runs = 0; mastered = false
        exercise = PracticeExercise(kind: .assessment, measures: 1...measureCount)
    }
    public mutating func learnNotes() { reassess(); exercise.kind = .notes }
    public mutating func skip() { advance() }
    public mutating func record(_ report: GradeReport, replays: Int = 0, completedNotes: Bool = false) {
        if exercise.kind == .assessment {
            mastered = report.passed && report.timing != nil && replays == 0
            guard !mastered else { return }
            let bar = RemediationPlanner.worstMeasure(in: [report])
            let range = bar.map { min(measureCount, max(1, $0))...min(measureCount, max(1, $0)) } ?? 1...measureCount
            let hasNoteErrors = report.notes.wrongPitch + report.notes.missed + report.notes.extra > 0
            queue = []
            if hasNoteErrors { queue.append(.init(kind: .notes, measures: range)) }
            queue.append(.init(kind: .slow, measures: range, tempoPercent: persona.drill.slowTempoPercent))
            queue.append(.init(kind: .fullSpeed, measures: range))
            let context = max(1, range.lowerBound - 1)...min(measureCount, range.upperBound + 1)
            if context != range { queue.append(.init(kind: .context, measures: context)) }
            advance(); return
        }
        runs += 1
        let clean = exercise.kind == .notes ? completedNotes : RemediationPlanner.isClean(report, replays: replays) && report.timing != nil
        cleanStreak = clean ? cleanStreak + 1 : 0
        if cleanStreak >= needed || (persona.drill.maxRunsPerStep.map { runs >= $0 } ?? false) { advance() }
    }
    private mutating func advance() {
        cleanStreak = 0; runs = 0
        exercise = queue.isEmpty ? .init(kind: .assessment, measures: 1...measureCount) : queue.removeFirst()
    }
}

public struct TutorAttemptContext: Codable, Sendable {
    public var exercise: PracticeExercise
    public var actualTempoPercent: Double
    public var mode: String
    public var printedMeasures: [Int]
    public init(exercise: PracticeExercise, actualTempoPercent: Double, mode: String, printedMeasures: [Int]) {
        self.exercise = exercise; self.actualTempoPercent = actualTempoPercent
        self.mode = mode; self.printedMeasures = printedMeasures
    }
}
