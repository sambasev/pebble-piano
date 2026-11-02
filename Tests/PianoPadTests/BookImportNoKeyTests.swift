#if os(macOS)
import XCTest
import PianoAI
@testable import PianoPad

/// Reading a book without a Meta key: saved readings still work, new ones ask for a key.
final class BookImportNoKeyTests: XCTestCase {
    private var sandbox: AppDataSandbox!

    override func setUp() { sandbox = AppDataSandbox("BookImportNoKey") }
    override func tearDown() { sandbox.remove() }

    private func uniqueImage() -> Data { Data(UUID().uuidString.utf8) }

    func testNewLineWithoutAKeyAsksForOne() async {
        do {
            _ = try await BookImportModel.cachedReading(png: uniqueImage(), client: nil, expectedMeasures: 2)
            XCTFail("Expected missingKey")
        } catch {
            XCTAssertEqual(error as? ModelError, .missingKey(.meta))
        }
    }

    func testSavedReadingWorksWithoutAKeyEvenWhenAskedToReadAgain() async throws {
        let png = uniqueImage()
        let url = BookImportModel.cacheURL(png: png, expectedMeasures: 2)
        try FileManager.default.createDirectory(at: BookImportModel.cacheFolder, withIntermediateDirectories: true)
        let saved = SystemReading(measureCount: 0, measures: [])
        try JSONEncoder().encode(saved).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let cached = try await BookImportModel.cachedReading(png: png, client: nil, expectedMeasures: 2)
        XCTAssertEqual(cached, saved)
        let again = try await BookImportModel.cachedReading(png: png, client: nil, expectedMeasures: 2, fresh: true)
        XCTAssertEqual(again, saved)
    }
}
#endif
