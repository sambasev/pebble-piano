#if canImport(PDFKit)
import PDFKit
import XCTest
@testable import PianoAI

/// The app's own demo book (Books/PianoPad-Starter-Book.pdf, made by scripts/make_demo_book.py
/// with LilyPond): find every system on every page as the importer does, measure it, and
/// compare each staff's pitches with the answer key the book was made from.
final class StarterBookTests: XCTestCase {
    static let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    struct Piece: Decodable {
        var title: String
        var clefs: [String]
        var measures: [[String: [[String]]]]
    }

    func testMeasuresEveryNoteInTheStarterBook() throws {
        let pdf = try XCTUnwrap(PDFDocument(url: Self.repo.appendingPathComponent("Books/PianoPad-Starter-Book.pdf")))
        let key = try JSONDecoder().decode([String: Piece].self, from: Data(contentsOf:
            Self.repo.appendingPathComponent("Fixtures/starter/truth/pieces.json")))
        // The pieces in book order (the JSON object's order isn't kept).
        let order = ["beyer-12", "beyer-13", "hot-cross-buns", "mary-had-a-little-lamb", "twinkle-twinkle",
                     "ode-to-joy", "lightly-row"]
        var want: [SystemReading.StaffName: [String]] = [.upper: [], .lower: []]
        for id in order {
            let piece = try XCTUnwrap(key[id], id)
            for bar in piece.measures {
                for staff in SystemReading.StaffName.allCases {
                    want[staff]! += (bar[staff.rawValue] ?? []).map { $0[0] }.filter { $0 != "r" }
                }
            }
        }

        var got: [SystemReading.StaffName: [String]] = [.upper: [], .lower: []]
        var systems = 0
        for i in 0..<pdf.pageCount {
            let (page, found) = try XCTUnwrap(BookImporter.page(pdf, index: i))
            for s in found {
                let system = try NoteheadGeometry.measure(SystemFinder.crop(page, s))
                systems += 1
                for staff in SystemReading.StaffName.allCases {
                    // Chord notes low to high, as the key lists them.
                    let heads = system.heads(staff).sorted { abs($0.x - $1.x) < 6 ? $0.y > $1.y : $0.x < $1.x }
                    got[staff]! += heads.map(\.pitch)
                }
            }
        }
        XCTAssertEqual(systems, 8)
        for staff in SystemReading.StaffName.allCases {
            XCTAssertEqual(got[staff]!, want[staff]!, "\(staff)")
        }
    }
}
#endif
