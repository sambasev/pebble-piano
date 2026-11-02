#if os(macOS)
import AppKit
import XCTest
@testable import PianoAI
@testable import PianoPad

/// Cancel, Start over and a new read while reading (or re-reading a bar) is still under way:
/// the late result is dropped instead of crashing or landing in the next piece.
@MainActor
final class BookImportLifecycleTests: XCTestCase {
    /// Holds a fake reader until the test lets it go.
    actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func open() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    private var env: BookTestEnvironment!
    private let source = BookImportModel.PieceSource(book: "Test.pdf", page: 0, lines: 0...0)
    private var model: BookImportModel!

    override func setUp() async throws {
        env = BookTestEnvironment()
        model = env.makeModel()
        // Every line measures as one bar, with no noteheads.
        model.measureLine = { _, _ in Self.geometry(bars: 1) }
        model.readLine = { _, _, _, _ in Self.reading(bars: 1) }
    }

    override func tearDown() async throws {
        env.tearDown(model)
    }

    nonisolated static func geometry(bars: Int) -> NoteheadGeometry.System {
        NoteheadGeometry.System(upper: .init(lines: [10, 20, 30, 40, 50], spacing: 10),
                                lower: .init(lines: [110, 120, 130, 140, 150], spacing: 10),
                                upperHeads: [], lowerHeads: [], barEdges: (0...bars).map { Double($0 * 100) })
    }

    /// Bars of one whole note in each hand: no notehead is measured, so each bar is to check
    /// (and the read stops at the check view). `rest`: bars of rests, nothing to check.
    nonisolated static func reading(bars: Int, rest: Bool = false) -> SystemReading {
        let staff = SystemReading.Staff(clef: .treble, notes: [.init(rest: rest, position: 4, duration: .whole)])
        return SystemReading(measureCount: bars, measures: Array(repeating: .init(upper: staff, lower: staff), count: bars))
    }

    /// One line to read; `tag` makes its image (and so its reading) distinct.
    func line(_ id: Int, tag: UInt8) -> BookImportModel.SystemRead {
        BookImportModel.SystemRead(id: id, found: FoundSystem(index: id, left: 0, top: 0, right: 100, bottom: 160, spacing: 10),
                                   gray: Gray(width: 100, height: 160, pixels: [UInt8](repeating: 255, count: 100 * 160)),
                                   png: Data([tag]), image: NSImage(size: NSSize(width: 100, height: 160)))
    }

    func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTFail("timed out", file: file, line: line)
    }

    func testCancelWhileReadingDropsTheRead() async {
        let gate = Gate()
        model.readLine = { _, _, _, _ in await gate.wait(); return Self.reading(bars: 1) }
        model.startReading([line(0, tag: 1), line(1, tag: 2)], source: source)
        await waitUntil { self.model.reads.allSatisfy { $0.step == .reading } }
        let reading = model.readTask

        model.startOver()  // Cancel
        await gate.open()
        await reading?.value

        XCTAssertEqual(model.phase, .choosing)
        XCTAssertTrue(model.reads.isEmpty)
        XCTAssertTrue(model.bars.isEmpty)
    }

    func testANewReadIsNotOverwrittenByTheOneItReplaced() async {
        let gate = Gate()
        model.readLine = { png, _, _, _ in
            if png == Data([1]) {  // the first piece: slow, three bars
                await gate.wait()
                return Self.reading(bars: 3)
            }
            return Self.reading(bars: 1)
        }
        model.startReading([line(0, tag: 1)], source: source)
        await waitUntil { self.model.reads.first?.step == .reading }
        let first = model.readTask

        model.startReading([line(0, tag: 2)], source: source)
        await model.readTask?.value
        await gate.open()
        await first?.value

        XCTAssertEqual(model.phase, .review)
        XCTAssertEqual(model.bars.count, 1, "the replaced read's three bars mustn't appear")
        XCTAssertEqual(model.reads.map(\.png), [Data([2])])
    }

    func testABarReReadAfterStartOverDoesntLandInTheNextPiece() async {
        model.startReading([line(0, tag: 1)], source: source)
        await model.readTask?.value
        XCTAssertEqual(model.bars.count, 1)

        let gate = Gate()
        model.barReader = { _, _, _ in
            await gate.wait()
            let note = SystemReading.Staff(clef: .treble, notes: [.init(position: 5, duration: .whole)])
            return SystemReading(measureCount: 1, measures: [.init(upper: note, lower: note)])
        }
        model.fix(1)
        XCTAssertEqual(model.fixing, [1])
        let fixing = model.fixTasks[1]

        model.startOver()
        XCTAssertTrue(model.fixing.isEmpty)
        model.startReading([line(0, tag: 2)], source: source)
        await model.readTask?.value
        await gate.open()
        await fixing?.value

        XCTAssertEqual(model.bars.count, 1)
        XCTAssertEqual(model.bars[0].bar.upper.map(\.note.position), [4], "the old re-read replaced bar 1 of the new piece")
        XCTAssertEqual(model.bars[0].bar, model.bars[0].original, "as read")
        XCTAssertNil(model.message)
    }

    func testAFailedReadCanBeTriedAgain() async {
        model.readLine = { png, _, _, _ in
            if png == Data([2]) { throw ModelError.badResponse("no connection") }
            return Self.reading(bars: 1)
        }
        model.startReading([line(0, tag: 1), line(1, tag: 2)], source: source)
        await model.readTask?.value
        XCTAssertEqual(model.phase, .choosing)
        XCTAssertTrue(model.canRetryRead)
        XCTAssertTrue(model.message?.hasPrefix("Some lines couldn't be read") == true, model.message ?? "")

        model.readLine = { _, _, _, _ in Self.reading(bars: 1) }
        model.startReading([line(0, tag: 1), line(1, tag: 2)], source: source)
        XCTAssertFalse(model.canRetryRead)
        await model.readTask?.value
        XCTAssertEqual(model.phase, .review)
    }

    func testAReadWithNothingToCheckIsSavedAndBackToPicking() async {
        model.readLine = { _, _, _, _ in Self.reading(bars: 1, rest: true) }
        model.title = "All rests"
        model.startReading([line(0, tag: 1)], source: source)
        await model.readTask?.value
        XCTAssertEqual(model.phase, .choosing)
        XCTAssertEqual(model.pieces.map(\.title), ["All rests"])
    }

    func testABarReReadStillLands() async {
        model.startReading([line(0, tag: 1)], source: source)
        await model.readTask?.value
        model.barReader = { _, _, _ in
            let note = SystemReading.Staff(clef: .treble, notes: [.init(position: 5, duration: .whole)])
            return SystemReading(measureCount: 1, measures: [.init(upper: note, lower: note)])
        }
        model.fix(1)
        await model.fixTasks[1]?.value

        XCTAssertTrue(model.fixing.isEmpty)
        XCTAssertEqual(model.bars[0].bar.upper.map(\.note.position), [5])
        XCTAssertTrue(model.bars[0].needsReview, "no heads were measured, so the re-read bar is flagged")
    }
}
#endif
