#if os(macOS)
import XCTest
@testable import PianoPad

final class GuidedTourTests: XCTestCase {
    func testEveryTourHasStepsEndingWithHowToComeBack() {
        for tour in TourID.allCases {
            let steps = tour.steps
            XCTAssertGreaterThan(steps.count, 1, "\(tour)")
            XCTAssertEqual(steps.last?.target, .help, "\(tour)")
        }
    }

    func testNoTourPointsAtTheSameThingTwice() {
        for tour in TourID.allCases {
            let targets = tour.steps.map(\.target)
            XCTAssertEqual(Set(targets).count, targets.count, "\(tour)")
        }
    }

    func testChildWordsFallBackToTheSame() {
        let step = TourStep(target: .music, title: "Notes", body: "The notes.")
        XCTAssertEqual(step.text(forChild: true), "The notes.")
        let kind = TourStep(target: .music, title: "Notes", body: "The notes.", childBody: "Play these!")
        XCTAssertEqual(kind.text(forChild: true), "Play these!")
        XCTAssertEqual(kind.text(forChild: false), "The notes.")
    }
}
#endif
