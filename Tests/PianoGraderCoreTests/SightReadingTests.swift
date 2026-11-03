import XCTest
@testable import PianoGraderCore

final class SightReadingTests: XCTestCase {
    private var allStages: [SightStage] { SightCurriculum.levels.flatMap(\.stages) }

    func testEveryStageMakesAFullQuizWithTheAnswerAmongTheChoices() {
        for stage in allStages {
            let quiz = SightQuestionGenerator.quiz(stage: stage.id, seed: 42)
            XCTAssertEqual(quiz.count, 10, stage.id.id)
            XCTAssertGreaterThanOrEqual(quiz[0].choices.count, 2, stage.id.id)
            for q in quiz {
                XCTAssertTrue(q.choices.contains(q.correctAnswer), q.id)
                XCTAssertEqual(Set(q.choices.map(\.id)).count, q.choices.count, "choices are distinct")
                XCTAssertEqual(q.playPitch != nil, stage.answersAtKeys, q.id)
            }
        }
    }

    func testQuizIsReproducibleCoversEveryAnswerAndNeverRepeatsAPicture() {
        let stage = SightStageID(level: 2, stage: 3)
        let a = SightQuestionGenerator.quiz(stage: stage, seed: 7, count: 20)
        let b = SightQuestionGenerator.quiz(stage: stage, seed: 7, count: 20)
        XCTAssertEqual(a.map(\.score), b.map(\.score))
        XCTAssertEqual(Set(a.prefix(7).map(\.correctAnswer.id)), ["C", "D", "E", "F", "G", "A", "B"],
                       "every letter comes up before any repeats")
        for (x, y) in zip(a, a.dropFirst()) { XCTAssertNotEqual(x.score, y.score) }
    }

    func testNoteNameQuestionsDrawTheirPitchInTheRightClef() {
        for (stage, clef) in [(SightStageID(level: 2, stage: 2), Clef.treble), (SightStageID(level: 3, stage: 2), .bass)] {
            for q in SightQuestionGenerator.examples(stage: stage) {
                XCTAssertEqual(q.score.staves, [clef])
                let note = q.score.measures[0].events[0].notes[0]
                XCTAssertEqual(note.midi, q.playPitch)
                XCTAssertEqual(note.spelled.letter, q.correctAnswer.id)
                // Line notes: every one sits on a line (even staff step).
                XCTAssertEqual(clef.staffStep(of: note.spelled) % 2, 0, q.explanation)
            }
        }
    }

    func testMiddleCIsNamedAsSuchInBothClefs() {
        let examples = SightQuestionGenerator.examples(stage: SightStageID(level: 1, stage: 3))
        let middleCs = examples.filter { $0.playPitch == 60 }
        XCTAssertEqual(middleCs.map(\.score.staves), [[.treble], [.bass]])
        XCTAssertTrue(middleCs.allSatisfy { $0.correctAnswer.title == "Middle C" })
        XCTAssertTrue(middleCs[0].explanation.contains("on the ledger line below the staff in the treble clef"))
        XCTAssertTrue(middleCs[1].explanation.contains("on the ledger line above the staff in the bass clef"))
    }

    func testValueQuestionsDrawTheValueTheyAskAbout() {
        let beats = SightQuestionGenerator.examples(stage: SightStageID(level: 4, stage: 2))
        let dotted = beats.first { $0.correctAnswer.id == "beats.3 beats" }!
        XCTAssertEqual(dotted.score.measures[0].events[0].type, .half)
        XCTAssertEqual(dotted.score.measures[0].events[0].dots, 1)
        XCTAssertEqual(dotted.score.measures[0].length, 12)
        let rests = SightQuestionGenerator.examples(stage: SightStageID(level: 5, stage: 2))
        XCTAssertTrue(rests.allSatisfy { $0.score.measures[0].events[0].isRest })
        XCTAssertEqual(rests.map(\.correctAnswer.title), ["Whole rest", "Half rest", "Quarter rest", "Eighth rest"])
        XCTAssertTrue(rests[3].explanation.hasSuffix("An eighth rest lasts ½ beat."))
    }

    func testStaffPlaces() {
        XCTAssertEqual(SightQuestionGenerator.place(0), "on line 1")
        XCTAssertEqual(SightQuestionGenerator.place(7), "in space 4")
        XCTAssertEqual(SightQuestionGenerator.place(-1), "just below the staff")
        XCTAssertEqual(SightQuestionGenerator.place(-3), "under the ledger line below the staff")
        XCTAssertEqual(SightQuestionGenerator.place(12), "on ledger line 2 above the staff")
    }

    func testQuizTakesChoicesOrTheExactKeyOnceEach() {
        var quiz = SightQuiz(questions: SightQuestionGenerator.quiz(stage: SightStageID(level: 2, stage: 1), seed: 1, count: 3))
        let first = quiz.question!
        XCTAssertFalse(quiz.next(), "can't move on before answering")
        XCTAssertTrue(quiz.submit(playedPitch: first.playPitch! + 12))
        XCTAssertEqual(quiz.response?.isCorrect, false, "the same letter an octave off is the wrong key")
        XCTAssertFalse(quiz.submit(answerID: first.correctAnswer.id), "answering twice does nothing")
        XCTAssertTrue(quiz.next())
        XCTAssertTrue(quiz.submit(playedPitch: quiz.question!.playPitch!))
        XCTAssertEqual(quiz.response?.isCorrect, true)
        XCTAssertTrue(quiz.next())
        XCTAssertTrue(quiz.submit(answerID: quiz.question!.correctAnswer.id))
        XCTAssertTrue(quiz.next())
        XCTAssertEqual(quiz.result?.correct, 2)
        XCTAssertEqual(quiz.result?.missed, [first.correctAnswer])
    }

    func testValueQuestionsIgnoreTheKeys() {
        var quiz = SightQuiz(questions: SightQuestionGenerator.quiz(stage: SightStageID(level: 4, stage: 1), seed: 1, count: 1))
        XCTAssertFalse(quiz.submit(playedPitch: 60))
        XCTAssertNil(quiz.response)
    }

    func testLayoutCanLeaveOutTheTimeSignature() {
        let score = SightQuestionGenerator.staff(.treble, .note(60, .whole))
        var metrics = ScoreLayout.Metrics()
        XCTAssertTrue(ScoreLayout(score: score, width: 300, metrics: metrics).systems[0].showsTimeSignature)
        metrics.timeSignature = false
        let layout = ScoreLayout(score: score, width: 300, metrics: metrics)
        XCTAssertFalse(layout.systems[0].showsTimeSignature)
        let digits = ScoreRenderer(layout: layout).renderScore().items.filter {
            if case .glyph(let g, _, _, _) = $0 { return g.rawValue.hasPrefix("timeSig") }; return false
        }
        XCTAssertTrue(digits.isEmpty)
    }
}
