import XCTest
@testable import PianoGraderCore

final class WaitGuideTests: XCTestCase {
    // D4, then a C–E–G chord, then F4.
    private func guide() -> WaitGuide { WaitGuide(chords: [[62], [60, 64, 67], [65]], settleWindow: 0.05) }

    func testRightNoteAdvancesAfterTheSettleWindow() {
        var g = guide()
        let due = g.noteOn(62, at: 1.0)
        XCTAssertEqual(due ?? 0, 1.05, accuracy: 1e-9)
        XCTAssertFalse(g.settle(at: 1.02))           // too early
        XCTAssertEqual(g.index, 0)
        XCTAssertTrue(g.settle(at: 1.05))
        XCTAssertEqual(g.index, 1)
        XCTAssertEqual(g.expected, [60, 64, 67])
    }

    func testAnExtraKeyStruckWithTheRightOneDoesNotPass() {
        var g = guide()
        g.noteOn(62, at: 1.0)
        g.noteOn(64, at: 1.01)                       // E with the D
        XCTAssertFalse(g.settle(at: 1.05))
        XCTAssertEqual(g.index, 0)
        XCTAssertEqual(g.wrongHeld, [64])
        // Letting go of E alone doesn't count: D has to be played again.
        g.noteOff(64)
        XCTAssertFalse(g.settle(at: 2.0))
        XCTAssertEqual(g.expected, [62])
        g.noteOff(62)
        let due = g.noteOn(62, at: 2.0)
        XCTAssertNotNil(due)
        XCTAssertTrue(g.settle(at: due!))
        XCTAssertEqual(g.index, 1)
    }

    func testAWrongKeyStruckFirstThenHeldBlocksTheRightOne() {
        var g = guide()
        g.noteOn(64, at: 1.0)                        // wrong, still held
        XCTAssertNil(g.noteOn(62, at: 1.2))
        XCTAssertFalse(g.settle(at: 2.0))
        g.noteOff(64)
        g.noteOff(62)
        // A wrong key let go, then the right one: that's correcting yourself, and it passes.
        let due = g.noteOn(62, at: 3.0)
        XCTAssertNotNil(due)
        XCTAssertTrue(g.settle(at: due!))
    }

    func testChordNeedsEveryNoteAndNothingElse() {
        var g = guide()
        g.settle(at: g.noteOn(62, at: 0)!)
        XCTAssertNil(g.noteOn(60, at: 1.0))
        XCTAssertNil(g.noteOn(64, at: 1.01))
        XCTAssertEqual(g.expected, [67])
        let due = g.noteOn(67, at: 1.02)
        XCTAssertNotNil(due)
        // A fourth key inside the settle window cancels the chord.
        g.noteOn(72, at: 1.03)
        XCTAssertFalse(g.settle(at: due!))
        XCTAssertEqual(g.index, 1)
        XCTAssertEqual(g.expected, [60, 64, 67])
    }

    func testKeysHeldFromThePreviousChordAreNotWrong() {
        var g = guide()
        g.settle(at: g.noteOn(62, at: 0)!)          // D still held (legato)
        g.noteOn(60, at: 0.5)
        g.noteOn(64, at: 0.5)
        let due = g.noteOn(67, at: 0.51)
        XCTAssertNotNil(due)
        XCTAssertTrue(g.settle(at: due!))
        XCTAssertEqual(g.index, 2)
        XCTAssertTrue(g.wrongHeld.isEmpty)
    }

    func testRepeatedNoteMustBeStruckAgain() {
        var g = WaitGuide(chords: [[60], [60]], settleWindow: 0)
        g.settle(at: g.noteOn(60, at: 0)!)
        XCTAssertEqual(g.index, 1)
        XCTAssertFalse(g.settle(at: 1))              // still holding the first C: not a new strike
        g.noteOff(60)
        g.settle(at: g.noteOn(60, at: 1)!)
        XCTAssertTrue(g.isFinished)
        XCTAssertNil(g.noteOn(62, at: 2))            // nothing left to wait for
    }

    func testLenientInputShowsExtraKeysWithoutBlocking() {
        var g = guide()
        g.noteOn(64, at: 1.0, strict: false)          // heard E with the D (maybe a mic artefact)
        let due = g.noteOn(62, at: 1.01, strict: false)
        XCTAssertEqual(g.wrongHeld, [64])             // still shown
        XCTAssertNotNil(due)
        XCTAssertTrue(g.settle(at: due!))             // but the D passes
        // A wrong key instead of the right one still doesn't pass.
        var h = guide()
        h.noteOn(64, at: 1.0, strict: false)
        XCTAssertFalse(h.settle(at: 2.0))
        XCTAssertEqual(h.index, 0)
    }

    func testReset() {
        var g = guide()
        g.settle(at: g.noteOn(62, at: 0)!)
        g.noteOn(70, at: 1)
        g.reset()
        XCTAssertEqual(g.index, 0)
        XCTAssertTrue(g.wrongHeld.isEmpty)
        XCTAssertEqual(g.expected, [62])
    }
}
