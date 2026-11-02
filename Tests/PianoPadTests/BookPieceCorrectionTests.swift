#if os(macOS)
import AppKit
import XCTest
@testable import PianoAI
import PianoGraderCore
@testable import PianoPad

/// A saved piece keeps its check: "Check and correct" reopens it as it was left, without
/// reading anything again, and saving it again keeps its folder.
@MainActor
final class BookPieceCorrectionTests: XCTestCase {
    private var env: BookTestEnvironment!
    private var model: BookImportModel!

    override func setUp() async throws {
        env = BookTestEnvironment()
        model = makeModel()
    }

    override func tearDown() async throws {
        env.tearDown(model)
    }

    /// Reads every line as one bar with one quarter note on the middle line, and measures no
    /// noteheads, so each bar is flagged to check.
    func makeModel() -> BookImportModel {
        let model = env.makeModel()
        model.measureLine = { _, _ in
            NoteheadGeometry.System(upper: .init(lines: [10, 20, 30, 40, 50], spacing: 10),
                                    lower: .init(lines: [110, 120, 130, 140, 150], spacing: 10),
                                    upperHeads: [], lowerHeads: [], barEdges: [0, 100])
        }
        model.readLine = { _, _, _, _ in
            let staff = SystemReading.Staff(clef: .treble, notes: [.init(position: 4, duration: .whole)])
            return SystemReading(measureCount: 1, measures: [.init(upper: staff, lower: staff)])
        }
        return model
    }

    func line(_ id: Int, index: Int) -> BookImportModel.SystemRead {
        let pixels: [UInt8] = (0..<16_000).map { (i: Int) -> UInt8 in UInt8(truncatingIfNeeded: i * 7 + id * 31) }
        let gray = Gray(width: 100, height: 160, pixels: pixels)
        return BookImportModel.SystemRead(id: id, found: FoundSystem(index: index, left: 0, top: 0, right: 100, bottom: 160, spacing: 10),
                                          gray: gray, png: gray.pngData()!, image: NSImage(size: NSSize(width: 100, height: 160)))
    }

    func source(_ lines: ClosedRange<Int>) -> BookImportModel.PieceSource {
        BookImportModel.PieceSource(book: "Test Book.pdf", page: 2, lines: lines)
    }

    /// Reads `lines` and checks every bar (nudging the first bar's top note up a step).
    func readAndCheck(_ lines: ClosedRange<Int>, title: String, on model: BookImportModel? = nil) async {
        let model = model ?? self.model!
        model.startReading(lines.enumerated().map { k, i in line(k, index: i) }, source: source(lines))
        await model.readTask?.value
        XCTAssertEqual(model.phase, .review)
        model.nudge(1, staff: .upper, note: 0, by: 1)
        for b in model.bars where b.needsReview { model.confirm(b.id) }
        model.title = title
    }

    func testSavingKeepsTheCheckAndReopensItAsLeft() async throws {
        await readAndCheck(0...1, title: "Exercise No. 13")
        let saved = try XCTUnwrap(model.store())
        XCTAssertEqual(saved.id, "Test Book p3 lines 1-2")
        for file in ["review.json", "line-0.png", "line-1.png", "score.json", "piece.mid"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: saved.folder.appendingPathComponent(file).path), file)
        }

        let again = makeModel()
        again.readLine = { _, _, _, _ in
            XCTFail("checking a saved piece mustn't read it again")
            throw ModelError.missingKey(.meta)
        }
        again.correct(saved)

        XCTAssertEqual(again.phase, .review)
        XCTAssertEqual(again.title, "Exercise No. 13")
        XCTAssertEqual(again.source, source(0...1))
        XCTAssertEqual(again.reads.count, 2)
        XCTAssertEqual(again.bars.map(\.bar), model.bars.map(\.bar))
        XCTAssertEqual(again.bars.map(\.original), model.bars.map(\.original))
        XCTAssertEqual(again.bars.map(\.resolution), [.nudged, .confirmed])
        XCTAssertEqual(again.bars[0].bar.upper[0].note.position, 5, "the nudge is kept")
        XCTAssertEqual(again.bars[0].original.upper[0].note.position, 4, "and so is the first reading")
        XCTAssertNotNil(again.bars[0].image, "the bar is cut from the saved line image")
        XCTAssertTrue(again.canSave)
    }

    func testRenamingKeepsTheFolder() async throws {
        await readAndCheck(0...0, title: "First name")
        let first = try XCTUnwrap(model.store())
        model.title = "Second name"
        let second = try XCTUnwrap(model.store())
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(model.pieces.map(\.title), ["Second name"])
    }

    func testDifferentLinesAreDifferentPiecesWhateverTheyreCalled() async throws {
        await readAndCheck(0...0, title: "Exercise 1, part A")
        let a = try XCTUnwrap(model.store())
        await readAndCheck(1...1, title: "Exercise 1 part A")
        let b = try XCTUnwrap(model.store())
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(model.pieces.count, 2)
    }

    /// A piece saved before checks were kept, named after its title.
    func legacyPiece() throws -> SavedPiece {
        let piece = SavedPiece(id: "Old title", title: "Old title", book: "Test Book.pdf", page: 2,
                               firstLine: 0, lastLine: 0, created: Date(timeIntervalSince1970: 0))
        try FileManager.default.createDirectory(at: piece.folder, withIntermediateDirectories: true)
        try BookLibrary.store(piece)
        try JSONEncoder().encode(ScoreWriter.write([], title: "Old title").score)
            .write(to: piece.folder.appendingPathComponent("score.json"))
        model.refreshLibrary()
        return piece
    }

    func testAnOlderPieceSavedAgainKeepsItsFolder() async throws {
        let old = try legacyPiece()
        await readAndCheck(0...0, title: "Old title")
        let saved = try XCTUnwrap(model.store())
        XCTAssertEqual(saved.id, old.id, "its lesson progress is filed under this folder")
        XCTAssertEqual(model.pieces.count, 1)
        XCTAssertNotNil(BookLibrary.correction(of: saved))
    }

    func testAnOlderPieceWithoutItsBookSaysSo() throws {
        let old = try legacyPiece()
        XCTAssertNil(BookLibrary.correction(of: old))
        model.correct(old)
        XCTAssertEqual(model.phase, .choosing)
        XCTAssertEqual(model.message, "Open Test Book.pdf first: it isn't in your books.")
    }

    func testABrokenCheckFallsBackToTheReadings() async throws {
        await readAndCheck(0...0, title: "Piece")
        let saved = try XCTUnwrap(model.store())
        try FileManager.default.removeItem(at: saved.folder.appendingPathComponent("line-0.png"))
        XCTAssertNil(BookLibrary.correction(of: saved))
    }

    // MARK: Lessons follow corrections

    func testCorrectedNotesMakeTheLessonAgainButKeepMarkedBars() async throws {
        await readAndCheck(0...1, title: "Piece")
        let saved = try XCTUnwrap(model.store())
        let lessons = PieceLessonStore.folder(saved.id)
        try FileManager.default.createDirectory(at: lessons, withIntermediateDirectories: true)
        let made = ["plan-a.json", "progress-a.json", "lesson.json", "whole.mid", "marks-a.json"]
        for file in made { try Data("x".utf8).write(to: lessons.appendingPathComponent(file)) }
        func kept() -> Set<String> {
            Set((try? FileManager.default.contentsOfDirectory(atPath: lessons.path)) ?? [])
        }

        model.title = "Renamed"
        model.store()
        XCTAssertEqual(kept(), Set(made), "a new name changes no note: the lesson stays")
        XCTAssertNil(model.lessonNote)

        model.nudge(2, staff: .lower, note: 0, by: 1)
        model.store()
        XCTAssertEqual(kept(), ["marks-a.json"])
        XCTAssertEqual(model.lessonNote,
                       "Your corrections changed bar 2 of Renamed, so its lesson will be planned again from the corrected notes.")
    }

    func testPrintedFingeringIsSavedAndKeptInPractice() async throws {
        model.readLine = { _, _, _, _ in
            let upper = SystemReading.Staff(clef: .treble, notes: [.init(position: 4, duration: .half, finger: 4),
                                                                   .init(position: 5, duration: .half)])
            let lower = SystemReading.Staff(clef: .bass, notes: [.init(position: 4, duration: .whole, finger: 2)])
            return SystemReading(measureCount: 1, measures: [.init(upper: upper, lower: lower)])
        }
        await readAndCheck(0...0, title: "Fingered")
        XCTAssertTrue(model.save())
        let piece = try XCTUnwrap(model.savedPiece(for: source(0...0)))
        XCTAssertEqual(BookLibrary.printedFingering(of: piece), [PrintedFinger(staff: 0, quarter: 0, finger: 4),
                                                                 PrintedFinger(staff: 1, quarter: 0, finger: 2)])
        let fingers = env.session.fingeringNotes
        XCTAssertEqual(fingers.first { $0.hand == .right && $0.quarter == 0 }?.finger, 4)
        XCTAssertEqual(fingers.first { $0.hand == .left && $0.quarter == 0 }?.finger, 2)
    }

    func testChangedBars() {
        func piece(_ positions: [Int]) -> Score {
            ScoreWriter.write(positions.map { p in
                let n = BarMerge.Note(note: .init(position: p, duration: .whole), clef: .treble)
                return BarMerge.Bar(upper: [n], lower: [], upperStatus: .confirmed, lowerStatus: .confirmed, pageBar: 0)
            }, title: "").score
        }
        XCTAssertEqual(BookImportModel.changedBars(piece([1, 2, 3]), piece([1, 2, 3])), [])
        XCTAssertEqual(BookImportModel.changedBars(piece([1, 2, 3]), piece([1, 5, 3])), [2])
        XCTAssertEqual(BookImportModel.changedBars(piece([1, 2, 3]), piece([1, 2])), [3], "a bar gone")
        XCTAssertEqual(BookImportModel.barList([2]), "bar 2")
        XCTAssertEqual(BookImportModel.barList([2, 5]), "bars 2 and 5")
        XCTAssertEqual(BookImportModel.barList([2, 3, 7]), "bars 2, 3 and 7")
    }

    func testAskingMuseWonderAgainIsForOneReadOnly() async {
        final class Asked: @unchecked Sendable { var how: [BookImportModel.ReadingSource] = [] }
        let asked = Asked()
        let read = model.readLine
        model.readLine = { png, measures, single, how in
            asked.how.append(how)
            return try await read(png, measures, single, how)
        }
        model.freshRead = true
        model.startReading([line(0, index: 0)], source: source(0...0))
        XCTAssertFalse(model.freshRead)
        await model.readTask?.value
        model.startReading([line(0, index: 0)], source: source(0...0))
        await model.readTask?.value
        XCTAssertEqual(asked.how, [.fresh, .saved])
    }
}
#endif
