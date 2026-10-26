import XCTest
@testable import PianoLessons

final class SongStagesTests: XCTestCase {
    func testOrderAndTitles() {
        XCTAssertEqual(SongStage.allCases, [.listen, .learn, .practise, .perform])
        XCTAssertEqual(SongStage.allCases.map(\.title), ["Listen", "Learn", "Practise", "Perform"])
        XCTAssertEqual(SongStage.listen.next, .learn)
        XCTAssertNil(SongStage.perform.next)
        XCTAssertTrue(SongStage.learn < SongStage.perform)
    }

    func testSuggestedFollowsWhatsFinished() {
        var p = SongProgress()
        XCTAssertEqual(p.current, .listen)
        XCTAssertEqual(p.suggested, .listen)
        XCTAssertEqual(p.finish(.listen), .learn)
        XCTAssertEqual(p.suggested, .learn)
        p.finish(.learn)
        p.finish(.practise)
        XCTAssertEqual(p.suggested, .perform)
        XCTAssertNil(p.finish(.perform))
        XCTAssertEqual(p.suggested, .perform, "all done: Perform stays the suggestion")
    }

    func testAnyStageCanBeOpened() {
        var p = SongProgress()
        p.go(to: .perform)
        XCTAssertEqual(p.current, .perform)
        XCTAssertFalse(p.usedHelp, "straight to Perform uses no help")
    }

    func testLearnOrPractiseCountsAsHelp() {
        var listened = SongProgress()
        listened.finish(.listen)
        XCTAssertFalse(listened.usedHelp, "listening isn't help")

        var learned = SongProgress()
        learned.finish(.learn)
        XCTAssertTrue(learned.usedHelp)

        var practised = SongProgress()
        practised.finish(.practise)
        XCTAssertTrue(practised.usedHelp)
    }

    func testResultPassesOnRequiredStars() {
        let s = PerformanceSummary(notes: 0.9, timing: 0.7, helpUsed: false)
        XCTAssertTrue(SongResult(stars: 1, summary: s, requiredStars: 1).passed)
        XCTAssertFalse(SongResult(stars: 1, summary: s, requiredStars: 2).passed)
        XCTAssertFalse(SongResult(stars: 0, summary: s, requiredStars: 1).passed)
    }
}
