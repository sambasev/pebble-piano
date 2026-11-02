#if os(macOS)
import PDFKit
import XCTest
import PianoAI
@testable import PianoPad

/// A piece's name is filled in from the heading over its first line.
final class BookTitleTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every line of the Starter Book: a piece's first line gets its heading, never the book's
    /// title or a time signature (bigger type than the heading, inside the same margin).
    func testTheStarterBooksHeadings() throws {
        let pdf = try XCTUnwrap(PDFDocument(url: Self.repo.appendingPathComponent("Books/PianoPad-Starter-Book.pdf")))
        var got: [[String?]] = []
        for i in 0..<pdf.pageCount {
            let page = try XCTUnwrap(pdf.page(at: i))
            let (_, found) = try XCTUnwrap(BookImporter.page(pdf, index: i))
            got.append(found.map { BookImportModel.heading(on: page, above: $0) })
        }
        XCTAssertEqual(got, [
            ["Exercise No. 12", "Exercise No. 13", "Hot Cross Buns", "Mary Had a Little Lamb", "Twinkle, Twinkle, Little Star"],
            [nil, "Ode to Joy", "Lightly Row"],
        ])
    }
}
#endif
