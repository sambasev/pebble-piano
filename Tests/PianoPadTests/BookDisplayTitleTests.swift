#if os(macOS)
import XCTest
@testable import PianoPad

final class BookDisplayTitleTests: XCTestCase {
    func testFileNamesBecomeReadableTitles() {
        XCTAssertEqual(LibraryBook.displayTitle("beyer-vorschule-book1"), "Beyer Vorschule Book 1")
        XCTAssertEqual(LibraryBook.displayTitle("beyer-vorschule-book1.pdf"), "Beyer Vorschule Book 1")
        XCTAssertEqual(LibraryBook.displayTitle("beyer_op101"), "Beyer Op 101")
        XCTAssertEqual(LibraryBook.displayTitle("the-art-of-finger-dexterity"), "The Art of Finger Dexterity")
    }

    func testTitlesWithSpacesAreKept() {
        XCTAssertEqual(LibraryBook.displayTitle("Pebble Piano Starter Book, Part 1"), "Pebble Piano Starter Book, Part 1")
        XCTAssertEqual(LibraryBook.displayTitle("MyBook"), "MyBook")
    }
}
#endif
