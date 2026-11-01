import XCTest
import PianoGraderCore
@testable import PianoLessons

final class EarLessonTests: XCTestCase {
    func testEarBlockDecodesDefaultsAndRoundTrips() throws {
        let block = try JSONDecoder().decode(Block.self, from: Data(#"{"type":"earTraining","level":1,"stage":1}"#.utf8))
        guard case .earTraining(let config) = block else { return XCTFail("Missing ear exercise") }
        XCTAssertEqual(config.questions, 5)
        XCTAssertEqual(config.passAccuracy, 0.8)
        XCTAssertTrue(block.isGraded)
        XCTAssertFalse(block.awardsStars)
        XCTAssertNil(block.midi)
        XCTAssertEqual(try JSONDecoder().decode(Block.self, from: JSONEncoder().encode(block)), block)
    }

    func testAllEightLevelsRemainAccessibleAsTwentyFourLessonPages() {
        let unit = EarLessonCourse.unit
        XCTAssertEqual(unit.pages.count, 24)
        let configs = unit.pages.flatMap(\.blocks).compactMap { block -> Block.EarTraining? in
            if case .earTraining(let b) = block { return b }; return nil
        }
        XCTAssertEqual(Set(configs.map(\.stageID)), Set(EarCurriculum.levels.flatMap(\.stages).map(\.id)))
        XCTAssertTrue(configs.allSatisfy { $0.questions == 10 })
        XCTAssertTrue(LoadedUnit(unit: unit, folder: URL(fileURLWithPath: "/unused")).validate().isEmpty)
    }

    func testEarExerciseRequiresResultAndSupportsRetryAndFlaggedSkip() {
        let page = LessonPage(id: "ear", title: "Listen", blocks: [.earTraining(.init(level: 1, stage: 1))])
        var engine = LessonEngine(page: page)
        XCTAssertTrue(engine.handle(.continueTapped).isEmpty)
        XCTAssertTrue(engine.handle(.notePlayed(pitch: 60)).isEmpty)
        XCTAssertEqual(engine.handle(.graded(.init(passed: false))), [.retry(attempt: 2)])
        XCTAssertFalse(engine.isComplete)
        _ = engine.handle(.graded(.init(passed: true)))
        XCTAssertTrue(engine.isComplete)
        XCTAssertNil(engine.result?.stars)
        var skipped = LessonEngine(page: page)
        _ = skipped.handle(.skip)
        XCTAssertEqual(skipped.result?.flaggedBlocks, [0])
    }

    func testValidationRejectsInvalidStageCountsThresholdsAndUnintroducedNotes() {
        let bad: [Block.EarTraining] = [
            .init(level: 9, stage: 1), .init(level: 1, stage: 4),
            .init(level: 1, stage: 1, questions: 0), .init(level: 1, stage: 1, passAccuracy: 1.1),
            .init(level: 1, stage: 1, notes: [0]), .init(level: 1, stage: 1, notes: [0, 11])]
        for config in bad {
            let unit = LoadedUnit(unit: LessonUnit(id: "test", title: "", pages: [
                LessonPage(id: "page", title: "", blocks: [.earTraining(config)])]), folder: URL(fileURLWithPath: "/unused"))
            XCTAssertEqual(unit.validate(), [.badEarTraining(page: "page", block: 0)])
        }
    }

    func testPianoChecksUseOnlyIntroducedNotesAndAppendAfterOriginalSteps() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let unit = try LoadedUnit.load(folder: root.appendingPathComponent("Lessons/unit1")).unit
        var introduced = Set<Int>()
        var checks = 0
        for page in unit.pages {
            introduced.formUnion(page.newNotes.map { $0.pitch % 12 })
            for (index, block) in page.blocks.enumerated() {
                if case .earTraining(let config) = block {
                    checks += 1
                    XCTAssertEqual(index, page.blocks.count - 1)
                    XCTAssertEqual(config.questions, 5)
                    XCTAssertTrue(Set(config.notes ?? []).isSubset(of: introduced))
                    let questions = EarQuestionGenerator.quiz(stage: config.stageID, seed: 1, count: 50, notes: config.notes)
                    XCTAssertEqual(questions.count, 50)
                    XCTAssertTrue(questions.flatMap(\.stimulus).allSatisfy { introduced.contains($0.pitch % 12) })
                }
            }
        }
        XCTAssertEqual(checks, 3)
    }

    func testEarCheckOnAPianoPageNamesItsNotes() {
        let e = [NoteName(pitch: 64)]
        XCTAssertEqual(EarCheckWording.eyebrow(newNotes: e), "Ear check: can you hear E?")
        XCTAssertEqual(EarCheckWording.prompt(newNotes: e, quizNotes: [0, 2, 4]),
                       "You just played C, D and E. Now find them by ear.")
        XCTAssertEqual(EarCheckWording.prompt(newNotes: [NoteName(pitch: 65)], quizNotes: [4, 0, 2, 5]),
                       "You just played C, D, E and F. Now find them by ear.")
        XCTAssertEqual(EarCheckWording.prompt(newNotes: e, quizNotes: nil), "You just played E. Now find it by ear.")
    }

    func testEarCourseKeepsTheGeneralWording() {
        XCTAssertEqual(EarCheckWording.eyebrow(newNotes: []), "Train your ear")
        XCTAssertEqual(EarCheckWording.prompt(newNotes: [], quizNotes: [0, 2]), "Listen, then choose what you hear.")
    }
}
