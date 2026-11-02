#if os(macOS)
import AppKit
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

    /// On "try the keyboard" steps note keys play; the tour's own keys still move it.
    @MainActor
    func testNoteKeysReachTheKeyboardOnlyOnItsStep() throws {
        let sandbox = AppDataSandbox("GuidedTour")
        defer { sandbox.remove() }
        let session = sandbox.session()
        session.startTour(.practice)
        let noteKey = try XCTUnwrap(Self.key(0, "a"))  // A: a white key
        let returnKey = try XCTUnwrap(Self.key(36, "\r"))

        XCTAssertTrue(session.handleTourKey(noteKey), "not a keyboard step: the tour takes it")
        session.tourLetsYouPlay = true
        XCTAssertFalse(session.handleTourKey(noteKey), "keyboard step: the note plays")
        XCTAssertTrue(session.handleTourKey(returnKey))
        XCTAssertEqual(session.tourStep, 1)
        XCTAssertTrue(TourID.allCases.flatMap(\.steps).filter(\.letsYouPlay).allSatisfy { $0.target == .keyboard })
    }

    private static func key(_ code: UInt16, _ chars: String) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                         context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)
    }
}
#endif
