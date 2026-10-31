import XCTest
@testable import PianoGraderCore

final class EarTrainingTests: XCTestCase {
    private let stages = EarCurriculum.levels.flatMap(\.stages)

    func testCurriculumHasEightOpenLevelsWithThreeStagesEach() {
        XCTAssertEqual(EarCurriculum.levels.map(\.id), Array(1...8))
        XCTAssertEqual(stages.count, 24)
        for level in EarCurriculum.levels { XCTAssertEqual(level.stages.map(\.id.stage), [1, 2, 3]) }
        XCTAssertNil(EarCurriculum.stage(EarStageID(level: 9, stage: 1)))
        XCTAssertTrue(EarQuestionGenerator.quiz(stage: EarStageID(level: 0, stage: 0), seed: 1).isEmpty)
        XCTAssertTrue(EarQuestionGenerator.quiz(stage: .first, seed: 1, count: 0).isEmpty)
        XCTAssertNil(EarStageID(level: 8, stage: 3).next)
    }

    func testNotePoolsAndThreeOctaveCoverage() {
        let pools = [[0, 2, 4], [0, 2, 4, 5, 7], [0, 2, 4, 5, 7, 9, 11],
                     [1, 3, 6, 8, 10], Array(0..<12), Array(0..<12)]
        for (index, stage) in stages.prefix(6).enumerated() {
            let questions = EarQuestionGenerator.quiz(stage: stage.id, seed: 100, count: 120)
            XCTAssertEqual(Set(questions.flatMap(\.stimulus).map { $0.pitch % 12 }), Set(pools[index]))
            XCTAssertEqual(questions[0].choices.count, pools[index].count)
            XCTAssertEqual(Set(questions.flatMap(\.stimulus).map { $0.pitch / 12 - 1 }), index == 5 ? [3, 4, 5] : [4])
            for question in questions {
                XCTAssertEqual(question.reference.map(\.pitch), [60])
                XCTAssertEqual(question.correctAnswer.id, "note.\(question.stimulus[0].pitch % 12)")
            }
        }
        XCTAssertEqual(EarCurriculum.pitchName(61), "C♯ / D♭")
    }

    func testQuestionsAreSeededBalancedAndHaveExactlyOneCorrectChoice() {
        for stage in stages {
            let questions = EarQuestionGenerator.quiz(stage: stage.id, seed: 1234, count: 120)
            let repeatQuestions = EarQuestionGenerator.quiz(stage: stage.id, seed: 1234, count: 120)
            XCTAssertEqual(questions.map(\.stimulus), repeatQuestions.map(\.stimulus))
            XCTAssertEqual(questions.map(\.choices), repeatQuestions.map(\.choices))
            XCTAssertEqual(questions.map(\.id), repeatQuestions.map(\.id))
            let counts = Dictionary(grouping: questions, by: \.correctAnswer.id).values.map(\.count)
            XCTAssertLessThanOrEqual((counts.max() ?? 0) - (counts.min() ?? 0), 1)
            for (index, question) in questions.enumerated() {
                XCTAssertEqual(question.choices.filter { $0.id == question.correctAnswer.id }.count, 1)
                XCTAssertEqual(Set(question.choices.map(\.id)).count, question.choices.count)
                if stage.id.level > 2 { XCTAssertLessThanOrEqual(question.choices.count, 4) }
                if index > 0 { XCTAssertNotEqual(question.stimulus, questions[index - 1].stimulus) }
                for note in question.stimulus + question.reference + question.solution {
                    XCTAssertTrue((0...127).contains(note.pitch))
                    XCTAssertGreaterThan(note.offset, note.onset)
                    XCTAssertGreaterThanOrEqual(note.onset, 0)
                }
            }
        }
    }

    func testLearningCoversEveryAnswerAndVariantWithoutAudioAmbiguity() {
        for stage in stages {
            let examples = EarQuestionGenerator.examples(stage: stage.id)
            XCTAssertFalse(examples.isEmpty)
            XCTAssertEqual(Set(examples.map(\.correctAnswer.id)),
                           Set(EarQuestionGenerator.quiz(stage: stage.id, seed: 42, count: 120).map(\.correctAnswer.id)))
            var fingerprints: [String: String] = [:]
            for example in examples {
                let signature = example.stimulus.map { "\($0.onset):\($0.pitch)" }.joined(separator: ",")
                if let existing = fingerprints[signature] { XCTAssertEqual(existing, example.correctAnswer.id) }
                fingerprints[signature] = example.correctAnswer.id
                XCTAssertEqual(example.solution, example.stimulus)
                XCTAssertFalse(example.explanation.isEmpty)
                XCTAssertFalse(example.solutionLabel.isEmpty)
            }
        }
    }

    func testTriadAndSeventhFormulas() {
        let triads = EarQuestionGenerator.examples(stage: EarStageID(level: 3, stage: 3))
        XCTAssertEqual(triads.map { $0.stimulus.map { $0.pitch - 48 } }, [[0, 4, 7], [0, 3, 7], [0, 3, 6], [0, 4, 8]])
        let sevenths = EarQuestionGenerator.examples(stage: EarStageID(level: 4, stage: 2))
        XCTAssertEqual(sevenths.map { $0.stimulus.map { $0.pitch - 48 } },
                       [[0, 4, 7, 11], [0, 3, 7, 10], [0, 4, 7, 10], [0, 3, 6, 10], [0, 3, 6, 9]])
    }

    func testInversionsNameTheBassAndDoNotIncludeSymmetricDiminishedSevenths() {
        let triads = EarQuestionGenerator.examples(stage: EarStageID(level: 4, stage: 1))
        XCTAssertEqual(triads.map { $0.stimulus[0].pitch - 48 }, [0, 4, 7, 0, 3, 7])
        let sevenths = EarQuestionGenerator.examples(stage: EarStageID(level: 4, stage: 3))
        XCTAssertEqual(sevenths.count, 16)
        XCTAssertEqual(sevenths.prefix(4).map { $0.stimulus[0].pitch - 48 }, [0, 4, 7, 11])
        XCTAssertTrue(sevenths.allSatisfy { $0.prompt.contains("inversion") })
        XCTAssertTrue(sevenths.allSatisfy { !$0.context.contains("Diminished 7") })
    }

    func testIntervalsCoverTwelveDistancesInAllThreeDirections() {
        let examples = EarQuestionGenerator.examples(stage: EarStageID(level: 5, stage: 2))
        XCTAssertEqual(examples.count, 36)
        for semitones in 1...12 {
            let variants = examples.filter { $0.correctAnswer.id == "interval.\(semitones)" }
            XCTAssertEqual(variants.count, 3)
            for variant in variants {
                XCTAssertEqual(abs(variant.stimulus[0].pitch - variant.stimulus[1].pitch), semitones)
            }
        }
        let descending = examples.first { $0.context.hasPrefix("Descending") }!
        XCTAssertGreaterThan(descending.stimulus[0].pitch, descending.stimulus[1].pitch)
        let harmonic = examples.first { $0.context.hasPrefix("Simultaneous") }!
        XCTAssertEqual(harmonic.stimulus[0].onset, harmonic.stimulus[1].onset)
    }

    func testMelodyChoicesHaveEqualLengthAndMatchScaleDegrees() {
        let questions = EarQuestionGenerator.quiz(stage: EarStageID(level: 5, stage: 3), seed: 99, count: 48)
        let scale = [0, 2, 4, 5, 7, 9, 11]
        for question in questions {
            let degrees = question.correctAnswer.title.split(separator: "–").map { Int($0)! }
            let base = question.stimulus[0].pitch
            XCTAssertEqual(question.stimulus.map { $0.pitch - base }, degrees.map { scale[$0 - 1] })
            XCTAssertTrue(question.choices.allSatisfy { $0.title.split(separator: "–").count == degrees.count })
        }
    }

    func testCadenceAndTurnaroundBassFormulas() {
        func basses(_ stage: EarStageID) -> [[Int]] {
            EarQuestionGenerator.examples(stage: stage).map { q in
                Dictionary(grouping: q.stimulus, by: \.onset).sorted { $0.key < $1.key }
                    .map { $0.value.map(\.pitch).min()! - 48 }
            }
        }
        XCTAssertEqual(basses(EarStageID(level: 6, stage: 1)), [[7, 0], [5, 0], [2, 7], [7, 9]])
        XCTAssertEqual(basses(EarStageID(level: 6, stage: 3)), [[0, 9, 2, 7], [0, 9, 2, 7], [0, 1, 2, 7]])
        let mixed = EarQuestionGenerator.examples(stage: EarStageID(level: 6, stage: 2))
        XCTAssertEqual(mixed[0].reference, mixed[1].reference)
        XCTAssertEqual(mixed[0].context, mixed[1].context)
        XCTAssertEqual(mixed[1].stimulus.filter { $0.onset == 0 }.map { $0.pitch - 48 }, [2, 5, 8, 12])
    }

    func testJazzFormulasRootlessContextAndModulationDestinations() {
        let ninths = EarQuestionGenerator.examples(stage: EarStageID(level: 7, stage: 1))
        XCTAssertEqual(ninths.map { $0.stimulus.map { $0.pitch - 48 } },
                       [[0, 4, 7, 11, 14], [0, 3, 7, 10, 14], [0, 4, 7, 10, 14]])
        let extended = EarQuestionGenerator.examples(stage: EarStageID(level: 7, stage: 2))
        XCTAssertEqual(extended.map { $0.stimulus.map { $0.pitch - 48 } },
                       [[0, 3, 10, 14, 17], [0, 4, 11, 14, 21], [0, 4, 10, 14, 21]])
        let altered = EarQuestionGenerator.examples(stage: EarStageID(level: 8, stage: 1))
        XCTAssertEqual(altered.map { $0.stimulus.filter { $0.onset > 0 }.map { $0.pitch - 48 } },
                       [[4, 10, 13, 19], [4, 10, 15, 19], [4, 10, 14, 18], [4, 10, 14, 20]])
        for q in altered {
            XCTAssertEqual(q.stimulus[0].pitch, 36)
            XCTAssertEqual(q.stimulus.filter { $0.onset > 0 }.count, 4)
            XCTAssertFalse(q.stimulus.filter { $0.onset > 0 }.contains { $0.pitch % 12 == 0 })
        }
        let modulations = EarQuestionGenerator.examples(stage: EarStageID(level: 8, stage: 3))
        XCTAssertEqual(modulations.map { $0.stimulus.last!.onset }, Array(repeating: 20.0 / 3, count: 4))
        XCTAssertEqual(modulations.map { q in q.stimulus.filter { $0.onset == 20.0 / 3 }.map(\.pitch).min()! - 48 }, [2, 3, 5, 7])
    }

    func testHigherLevelsUseAllTwelveRootsAndDifferentVoicings() {
        for stage in stages where stage.id.level >= 3 {
            let questions = EarQuestionGenerator.quiz(stage: stage.id, seed: 888, count: 240)
            XCTAssertEqual(Set(questions.map { $0.reference[0].pitch % 12 }), Set(0..<12))
        }
        let open = EarQuestionGenerator.quiz(stage: EarStageID(level: 7, stage: 3), seed: 5, count: 60)
        let majorNinths = open.filter { $0.correctAnswer.id == "maj9" }
        XCTAssertGreaterThan(Set(majorNinths.map { ($0.stimulus.first!.pitch - $0.reference[0].pitch) % 12 }).count, 1)
        XCTAssertTrue(majorNinths.contains { $0.stimulus.last!.pitch - $0.reference[0].pitch >= 24 })
        for question in majorNinths {
            XCTAssertEqual(Set(question.stimulus.map { ($0.pitch - question.reference[0].pitch) % 12 }), [0, 2, 4, 7, 11])
        }
    }

    func testQuizRequiresOneAnswerThenExplicitNextAndCountsSkips() {
        var quiz = EarQuiz(questions: EarQuestionGenerator.quiz(stage: .first, seed: 1))
        XCTAssertFalse(quiz.next())
        XCTAssertFalse(quiz.submit(answerID: "invalid"))
        for i in 0..<10 {
            let q = quiz.question!
            XCTAssertEqual(quiz.index, i)
            XCTAssertTrue(quiz.submit(answerID: i < 8 ? q.correctAnswer.id : nil))
            XCTAssertFalse(quiz.submit(answerID: q.correctAnswer.id))
            XCTAssertEqual(quiz.index, i)
            XCTAssertTrue(quiz.next())
        }
        XCTAssertTrue(quiz.isFinished)
        XCTAssertNil(quiz.question)
        XCTAssertFalse(quiz.next())
        XCTAssertEqual(quiz.result?.correct, 8)
        XCTAssertEqual(quiz.result?.total, 10)
        XCTAssertEqual(quiz.result?.recommendedStage, EarStageID(level: 1, stage: 2))
        XCTAssertFalse(quiz.result!.missed.isEmpty)
    }

    func testUnfinishedQuizHasNoResultAndThresholdDoesNotLockStages() {
        var quiz = EarQuiz(questions: EarQuestionGenerator.quiz(stage: .first, seed: 5))
        quiz.submit(answerID: quiz.question!.correctAnswer.id)
        XCTAssertNil(quiz.result)
        let low = EarQuizResult(stage: .first, correct: 7, total: 10, missed: [])
        XCTAssertFalse(low.shouldAdvance)
        XCTAssertEqual(low.recommendedStage, .first)
        XCTAssertNotNil(EarCurriculum.stage(EarStageID(level: 8, stage: 3)))
    }

    func testProgressRoundTripBestScoreRecommendationsAndInvalidStorage() throws {
        var progress = EarProgress()
        progress.record(EarQuizResult(stage: .first, correct: 9, total: 10, missed: []))
        progress.record(EarQuizResult(stage: .first, correct: 6, total: 10, missed: []))
        XCTAssertEqual(progress.stages["1.1"]?.bestCorrect, 9)
        XCTAssertEqual(progress.stages["1.1"]?.completedQuizzes, 2)
        XCTAssertEqual(progress.recommendedStage, .first)
        XCTAssertEqual(EarProgress.decode(try JSONEncoder().encode(progress)), progress)
        XCTAssertEqual(EarProgress.decode(nil), EarProgress())
        XCTAssertEqual(EarProgress.decode(Data("broken".utf8)), EarProgress())
        let invalid = Data("{\"version\":2,\"stages\":{},\"recommendedStage\":{\"level\":1,\"stage\":1}}".utf8)
        XCTAssertEqual(EarProgress.decode(invalid), EarProgress())
        let badScore = Data("{\"version\":1,\"stages\":{\"1.1\":{\"bestCorrect\":99,\"completedQuizzes\":1}},\"recommendedStage\":{\"level\":1,\"stage\":1}}".utf8)
        XCTAssertEqual(EarProgress.decode(badScore), EarProgress())
        let final = EarStageID(level: 8, stage: 3)
        progress.record(EarQuizResult(stage: final, correct: 10, total: 10, missed: []))
        XCTAssertEqual(progress.recommendedStage, final)
    }
}
