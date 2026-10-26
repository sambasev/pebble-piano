import XCTest
@testable import PianoLessons

final class CoachTests: XCTestCase {
    /// p1 → p2 → p3 → p4 in a chain; p2 and p4 have a starred (timed) block.
    private let unit: LessonUnit = {
        func page(_ id: String, unlocks: String?, starred: Bool) -> LessonPage {
            let block: Block = starred ? .timed(.init(midi: "x.mid", tempo: 80)) : .wait(.init(midi: "x.mid"))
            return LessonPage(id: id, title: id.uppercased(), blocks: [block], unlocks: unlocks)
        }
        return LessonUnit(id: "u1", title: "Unit", pages: [
            page("p1", unlocks: "p2", starred: false),
            page("p2", unlocks: "p3", starred: true),
            page("p3", unlocks: "p4", starred: false),
            page("p4", unlocks: nil, starred: true),
        ])
    }()

    private func next(_ states: [String: CoachPageState]) -> String? {
        Coach.nextPage(in: unit, states: states)?.id
    }

    func testStartsAtTheFirstPage() {
        XCTAssertEqual(next([:]), "p1")
    }

    func testNextUnlockedPage() {
        XCTAssertEqual(next(["p1": .init(completed: true)]), "p2")
    }

    func testUnfinishedPageComesFirst() {
        // p1 and p2 done, but p1 was finished with a step skipped.
        let states: [String: CoachPageState] = [
            "p1": .init(completed: true, flagged: true),
            "p2": .init(completed: true, bestStars: 2),
        ]
        XCTAssertEqual(next(states), "p1")
    }

    func testFewestStarsAmongUnfinished() {
        let states: [String: CoachPageState] = [
            "p1": .init(completed: true, bestStars: nil, flagged: true),
            "p2": .init(completed: true, bestStars: 3, flagged: true),
            "p3": .init(completed: true, flagged: true),
            "p4": .init(inProgress: true),
        ]
        // p1, p3 and p4 all have no stars: the first in unit order.
        XCTAssertEqual(next(states), "p1")
    }

    func testInProgressPage() {
        let states: [String: CoachPageState] = [
            "p1": .init(completed: true),
            "p2": .init(completed: true, bestStars: 1),
            "p3": .init(inProgress: true),
        ]
        XCTAssertEqual(next(states), "p3")
    }

    func testLockedPagesAreNeverSuggested() {
        // A saved position on a page that isn't unlocked (it shouldn't happen) is ignored.
        XCTAssertEqual(next(["p3": .init(inProgress: true)]), "p1")
    }

    func testAllDoneSuggestsTheWeakestStarredPage() {
        let done: [String: CoachPageState] = [
            "p1": .init(completed: true),
            "p2": .init(completed: true, bestStars: 2),
            "p3": .init(completed: true),
            "p4": .init(completed: true, bestStars: 1),
        ]
        XCTAssertEqual(next(done), "p4")
        var perfect = done
        perfect["p2"]?.bestStars = 3
        perfect["p4"]?.bestStars = 3
        XCTAssertNil(next(perfect))
    }

    func testWarmUpDrop() {
        XCTAssertFalse(Coach.warmUpSuggestsReview(previous: 0.95, now: 0.80))
        XCTAssertFalse(Coach.warmUpSuggestsReview(previous: 0.95, now: 0.75)) // exactly 20 points
        XCTAssertTrue(Coach.warmUpSuggestsReview(previous: 0.95, now: 0.70))
        XCTAssertFalse(Coach.warmUpSuggestsReview(previous: 0.60, now: 0.90))
    }
}
