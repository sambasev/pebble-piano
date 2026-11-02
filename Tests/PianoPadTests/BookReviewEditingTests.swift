#if os(macOS)
import AppKit
import XCTest
@testable import PianoAI
@testable import PianoPad

/// Correcting bars in the review: picking a bar and a note, changing it, Undo/Redo, Revert.
@MainActor
final class BookReviewEditingTests: XCTestCase {
    private var env: BookTestEnvironment!
    private var model: BookImportModel!

    /// Two lines of two bars each (a treble staff over a bass staff), the music starting 40 px in
    /// (after the clefs). Line 0's bars
    /// are trusted (one head measured per staff, matching the reading); line 1 measured no
    /// heads, so its bars are to check.
    override func setUp() async throws {
        env = BookTestEnvironment()
        model = env.makeModel()
        let staff = NoteheadGeometry.Staff(lines: [10, 20, 30, 40, 50], spacing: 10)
        let low = NoteheadGeometry.Staff(lines: [110, 120, 130, 140, 150], spacing: 10)
        model.measureLine = { png, _ in
            let measured = png == Data([0])
            func heads(_ y: Double) -> [NoteheadGeometry.Head] {
                measured ? [50, 150].map { .init(x: $0, y: y, position: 4, offset: 0, filled: false, pitch: "") } : []
            }
            return NoteheadGeometry.System(upper: staff, lower: low, upperHeads: heads(30), lowerHeads: heads(130),
                                           barEdges: [40, 120, 200])
        }
        model.readLine = { _, _, _, _ in
            let note = SystemReading.Note(position: 4, duration: .whole)
            let measure = SystemReading.Measure(upper: .init(clef: .treble, notes: [note]), lower: .init(clef: .bass, notes: [note]))
            return SystemReading(measureCount: 2, measures: [measure, measure])
        }
        let lines = (0..<2).map { k in
            BookImportModel.SystemRead(id: k, found: FoundSystem(index: k, left: 0, top: 0, right: 200, bottom: 160, spacing: 10),
                                       gray: Gray(width: 200, height: 160, pixels: [UInt8](repeating: 255, count: 200 * 160)),
                                       png: Data([UInt8(k)]), image: NSImage(size: NSSize(width: 200, height: 160)),
                                       lowerClef: .bass)
        }
        model.startReading(lines, source: .init(book: "Test.pdf", page: 0, lines: 0...1))
        await model.readTask?.value
        XCTAssertEqual(model.bars.map(\.resolution), [.trusted, .trusted, .needsReview, .needsReview])
    }

    override func tearDown() async throws {
        env.tearDown(model)
    }

    var bar3: BookImportModel.ReviewBar { model.bars[2] }

    func testTheFirstBarToCheckIsOpen() {
        XCTAssertEqual(model.selectedBar, 3)
        model.selectNext(toCheck: true)
        XCTAssertEqual(model.selectedBar, 4)
        model.selectNext(toCheck: true)
        XCTAssertEqual(model.selectedBar, 3, "round to the start")
        model.selectNext(toCheck: false)
        XCTAssertEqual(model.selectedBar, 4)
        model.selectNext(toCheck: false)
        XCTAssertEqual(model.selectedBar, 1)
        model.selectNext(toCheck: false, step: -1)
        XCTAssertEqual(model.selectedBar, 4)
    }

    func testPickingAnotherBarLetsGoOfTheNote() {
        model.select(note: .init(staff: .upper, index: 0))
        model.select(bar: 1)
        XCTAssertNil(model.selectedNote)
    }

    func testAnEditCorrectsTheBarAndCanBeUndoneAndRedone() {
        let before = bar3
        let note = BookImportModel.NoteRef(staff: .upper, index: 0)
        model.setDuration(3, note, .half)
        XCTAssertEqual(bar3.bar.upper[0].note.duration, .half)
        XCTAssertEqual(bar3.resolution, .nudged)
        XCTAssertEqual(model.toReview, 1)

        model.undo()
        XCTAssertEqual(bar3, before)
        XCTAssertTrue(model.canRedo)
        model.redo()
        XCTAssertEqual(bar3.bar.upper[0].note.duration, .half)

        model.undo()
        model.cycleAccidental(3, note)
        XCTAssertFalse(model.canRedo, "a new change drops what was undone")
        XCTAssertEqual(bar3.bar.upper[0].note.accidental, .sharp)
    }

    func testAnEditThatChangesNothingIsntRemembered() {
        model.nudge(3, staff: .upper, note: 9, by: 1)
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(bar3.resolution, .needsReview)
    }

    func testConfirmMarkToCheckAndRevert() {
        model.confirm(3)
        XCTAssertEqual(bar3.resolution, .confirmed)
        model.markToCheck(3)
        XCTAssertEqual(bar3.resolution, .needsReview)

        model.nudge(3, staff: .lower, note: 0, by: -2)
        model.toggleRest(3, .init(staff: .upper, index: 0))
        XCTAssertNotEqual(bar3.bar, bar3.original)
        model.revert(3)
        XCTAssertEqual(bar3.bar, bar3.original)
        XCTAssertEqual(bar3.resolution, .needsReview, "as first read: still to check")
        model.undo()
        XCTAssertTrue(bar3.bar.upper[0].note.rest, "Revert can be undone too")
    }

    func testAddingANotePicksItAndDeletingLetsGo() {
        model.select(bar: 3)
        model.insertNote(3, staff: .upper, after: nil)
        XCTAssertEqual(bar3.bar.upper.count, 2)
        XCTAssertEqual(model.selectedNote, .init(staff: .upper, index: 1))
        model.deleteNote(3, .init(staff: .upper, index: 1))
        XCTAssertEqual(bar3.bar.upper.count, 1)
        XCTAssertNil(model.selectedNote)
    }

    func testAClefChangesTheWholeLineInOneStep() {
        XCTAssertEqual(model.staffClef(inSystem: 1, .lower), .bass)
        model.setClef(inSystem: 1, .lower, .treble)
        XCTAssertEqual(model.bars(inSystem: 1).map { $0.bar.lower[0].clef }, [.treble, .treble])
        XCTAssertEqual(model.bars(inSystem: 1).map(\.resolution), [.nudged, .nudged])
        XCTAssertEqual(model.bars(inSystem: 0).map { $0.bar.lower[0].clef }, [.bass, .bass], "other lines stay")
        model.undo()
        XCTAssertEqual(model.bars(inSystem: 1).map { $0.bar.lower[0].clef }, [.bass, .bass])
        XCTAssertFalse(model.canUndo)
    }

    // MARK: Reading a bar again

    /// A reply for one bar: both staves a whole note at `position`, in these clefs.
    nonisolated static func reply(_ position: Int, upper: SystemReading.Clef = .treble,
                                  lower: SystemReading.Clef = .bass) -> SystemReading {
        let note = SystemReading.Note(position: position, duration: .whole)
        return SystemReading(measureCount: 1, measures: [.init(upper: .init(clef: upper, notes: [note]),
                                                               lower: .init(clef: lower, notes: [note]))])
    }

    func testAReReadKeepsTheLinesClefs() async {
        // A crop's clefs are the model's guess: here it gets them the wrong way round.
        model.barReader = { _, _, _ in Self.reply(4, upper: .bass, lower: .treble) }
        await model.fix(1)?.value
        XCTAssertEqual(model.bars[0].bar.upper[0].clef, .treble)
        XCTAssertEqual(model.bars[0].bar.lower[0].clef, .bass)
        XCTAssertEqual(model.bars[0].bar.noteNames(.upper), ["B4"])
        XCTAssertFalse(model.canUndo, "the same bar as before: nothing changed")
    }

    func testTheCropShowsTheStartOfTheLine() async throws {
        final class Sent: @unchecked Sendable { var widths: [Int] = [] }
        let sent = Sent()
        model.barReader = { png, _, _ in
            sent.widths.append(Gray.decode(png)?.width ?? 0)
            return Self.reply(4)
        }
        await model.fix(2)?.value  // bar 114…200 (with its margin), after the line's first 40 px
        await model.fix(1)?.value  // the first bar: the start of the line is already in it
        XCTAssertEqual(sent.widths, [40 + 6 + 86, 126])
    }

    func testABarAsFirstReadTakesTheNewReading() async {
        model.barReader = { _, _, _ in Self.reply(6) }
        await model.fix(3)?.value
        XCTAssertNil(model.proposals[3])
        XCTAssertEqual(bar3.bar.upper[0].note.position, 6)
        XCTAssertEqual(bar3.resolution, .needsReview, "no heads measured to check it: still to check")
        XCTAssertEqual(bar3.original.upper[0].note.position, 4, "Revert still brings the first reading back")
    }

    func testACorrectedBarGetsTheNewReadingAsAProposal() async {
        model.nudge(3, staff: .upper, note: 0, by: 1)
        let mine = bar3.bar
        model.barReader = { _, _, _ in Self.reply(7) }
        await model.fix(3)?.value
        XCTAssertEqual(bar3.bar, mine, "a correction isn't replaced unasked")
        XCTAssertEqual(model.proposals[3]?.upper[0].note.position, 7)

        model.useProposal(3)
        XCTAssertEqual(bar3.bar.upper[0].note.position, 7)
        XCTAssertNil(model.proposals[3])
        model.undo()
        XCTAssertEqual(bar3.bar, mine, "Use this can be undone")

        await model.fix(3)?.value
        model.dismissProposal(3)
        XCTAssertNil(model.proposals[3])
        XCTAssertEqual(bar3.bar, mine)
    }

    func testACheckedBarGetsAProposalToo() async {
        model.confirm(3)
        model.barReader = { _, _, _ in Self.reply(7) }
        await model.fix(3)?.value
        XCTAssertNotNil(model.proposals[3])
        XCTAssertEqual(bar3.resolution, .confirmed)
    }

    func testFixThisBarAsksAgainButAReadUsesSavedReReadings() async {
        final class Asked: @unchecked Sendable { var fresh: [Bool] = [] }
        let asked = Asked()
        model.barReader = { _, _, fresh in
            asked.fresh.append(fresh)
            return Self.reply(4)
        }
        await model.fix(3)?.value
        XCTAssertEqual(asked.fresh, [true])

        // A line whose reading skipped one of its two bars: that bar is read again during the read.
        model.readLine = { _, _, _, _ in
            let note = SystemReading.Note(position: 4, duration: .whole)
            return SystemReading(measureCount: 1, measures: [.init(upper: .init(clef: .treble, notes: [note]),
                                                                   lower: .init(clef: .bass, notes: [note]))])
        }
        model.startReading([model.reads[0]], source: .init(book: "Test.pdf", page: 0, lines: 0...0))
        await model.readTask?.value
        // Let the read finish (with nothing left to check, it saves the piece).
        for _ in 0..<500 where model.phase == .reading { try? await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertEqual(asked.fresh, [true, false])
    }

    func testANewReviewDropsProposals() async {
        model.confirm(3)
        model.barReader = { _, _, _ in Self.reply(7) }
        await model.fix(3)?.value
        model.startOver()
        XCTAssertTrue(model.proposals.isEmpty)
    }

    func testTheMetreIsWhatTheBarsAddUpTo() {
        XCTAssertEqual(model.metre.numerator, 4)
        XCTAssertEqual(model.metre.denominator, 4)
    }

    func testANewReviewStartsWithNoHistory() {
        model.confirm(3)
        model.startOver()
        XCTAssertFalse(model.canUndo)
        XCTAssertNil(model.selectedBar)
    }
}
#endif
