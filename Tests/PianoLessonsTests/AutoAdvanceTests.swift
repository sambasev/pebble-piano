import XCTest
@testable import PianoLessons

final class AutoAdvanceTests: XCTestCase {
    func testReadingScalesWithWordsWithinBounds() {
        XCTAssertEqual(AutoAdvance.seconds(.reading(words: 0)), 3, "never shorter than 3 s")
        XCTAssertEqual(AutoAdvance.seconds(.reading(words: 14)), 5.5, accuracy: 0.001)
        XCTAssertEqual(AutoAdvance.seconds(.reading(words: 200)), 8, "never longer than 8 s")
    }

    func testChildrenGetLonger() {
        XCTAssertEqual(AutoAdvance.seconds(.pageDone, child: true), AutoAdvance.seconds(.pageDone) * 1.5, accuracy: 0.001)
        XCTAssertGreaterThan(AutoAdvance.seconds(.reading(words: 10), child: true), AutoAdvance.seconds(.reading(words: 10)))
    }

    func testPageDoneIsTheLongestFixedWait() {
        let fixed: [AutoAdvance.Moment] = [.choiceMade, .checkPassed, .setupInfo, .stageDone, .warmUpDone, .drillStarts]
        for m in fixed { XCTAssertLessThan(AutoAdvance.seconds(m), AutoAdvance.seconds(.pageDone)) }
    }

    func testWordCount() {
        XCTAssertEqual(AutoAdvance.wordCount("D is the white key  between\nthe 2 black keys"), 9)
        XCTAssertEqual(AutoAdvance.wordCount(""), 0)
    }
}
