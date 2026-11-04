import XCTest
import PianoGraderCore
@testable import PianoLessons

final class SightReadingCourseTests: XCTestCase {
    func testBlockDecodesDefaultsAndRoundTrips() throws {
        let block = try JSONDecoder().decode(Block.self, from: Data(#"{"type":"sightReading","level":2,"stage":1}"#.utf8))
        guard case .sightReading(let config) = block else { return XCTFail("Missing sight-reading quiz") }
        XCTAssertEqual(config.questions, 5)
        XCTAssertEqual(config.passAccuracy, 0.8)
        XCTAssertTrue(block.isGraded)
        XCTAssertFalse(block.awardsStars)
        XCTAssertNil(block.midi)
        XCTAssertEqual(try JSONDecoder().decode(Block.self, from: JSONEncoder().encode(block)), block)
    }

    func testCourseHasALessonAndQuizPagePerStageChainedInOrder() {
        let unit = SightReadingCourse.unit
        let stages = SightCurriculum.levels.flatMap(\.stages)
        XCTAssertEqual(unit.pages.count, stages.count)
        for (page, stage) in zip(unit.pages, stages) {
            XCTAssertEqual(page.blocks.map(\.kind), [.explain, .sightReading])
            guard case .sightReading(let b) = page.blocks[1] else { return XCTFail() }
            XCTAssertEqual(b.stageID, stage.id)
        }
        XCTAssertEqual(unit.pages.dropLast().map(\.unlocks), unit.pages.dropFirst().map(\.id))
        XCTAssertTrue(LoadedUnit(unit: unit, folder: URL(fileURLWithPath: "/unused")).validate().isEmpty)
    }

    func testValidationRejectsUnknownStagesCountsAndThresholds() {
        let bad: [Block.SightReading] = [.init(level: 9, stage: 1), .init(level: 1, stage: 4),
                                         .init(level: 1, stage: 1, questions: 0), .init(level: 1, stage: 1, passAccuracy: 1.5)]
        for config in bad {
            let unit = LoadedUnit(unit: LessonUnit(id: "test", title: "", pages: [
                LessonPage(id: "page", title: "", blocks: [.sightReading(config)])]), folder: URL(fileURLWithPath: "/unused"))
            XCTAssertEqual(unit.validate(), [.badSightReading(page: "page", block: 0)])
        }
    }

    func testQuizNeedsAPassingResultToMoveOn() {
        let page = LessonPage(id: "read", title: "Read", blocks: [.sightReading(.init(level: 1, stage: 1))])
        var engine = LessonEngine(page: page)
        XCTAssertTrue(engine.handle(.continueTapped).isEmpty)
        XCTAssertEqual(engine.handle(.graded(.init(passed: false))), [.retry(attempt: 2)])
        _ = engine.handle(.graded(.init(passed: true)))
        XCTAssertTrue(engine.isComplete)
    }
}
