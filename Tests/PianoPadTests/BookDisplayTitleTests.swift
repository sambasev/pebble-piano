#if os(macOS)
import XCTest
@testable import PianoPad

final class BookDisplayTitleTests: XCTestCase {
    func testFileNamesBecomeReadableTitles() {
        XCTAssertEqual(LibraryBook.displayTitle("learning-the-code-book1"), "Learning the Code Book 1")
        XCTAssertEqual(LibraryBook.displayTitle("learning-the-code-book1.pdf"), "Learning the Code Book 1")
        XCTAssertEqual(LibraryBook.displayTitle("beyer_op101"), "Beyer Op 101")
        XCTAssertEqual(LibraryBook.displayTitle("the-art-of-finger-dexterity"), "The Art of Finger Dexterity")
    }

    func testTitlesWithSpacesAreKept() {
        XCTAssertEqual(LibraryBook.displayTitle("Learning the Code, Book 1"), "Learning the Code, Book 1")
        XCTAssertEqual(LibraryBook.displayTitle("MyBook"), "MyBook")
    }
}
#endif
