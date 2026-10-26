import XCTest
@testable import PianoLessons

final class LessonEngineTests: XCTestCase {
    /// find (Continue) → read (play C4) → wait → listen → timed (starred)
    let page = LessonPage(id: "p1", title: "Meet Middle C", newNotes: [NoteName(pitch: 60)], blocks: [
        .explain(.init(text: "Find the 2 black keys", highlight: [NoteName(pitch: 61), NoteName(pitch: 63)])),
        .explain(.init(text: "This is Middle C", highlight: [NoteName(pitch: 60)], advanceOn: NoteName(pitch: 60))),
        .wait(.init(midi: "ex1.mid", prompt: "Play the note C", fingering: [1, 1, 1], hand: .right)),
        .listen(.init(midi: "ex2.mid", tempo: 60)),
        .timed(.init(midi: "ex2.mid", tempo: 60)),
    ], unlocks: "p2")

    /// Moves an engine to the wait block (index 2).
    private func atWaitBlock(_ rules: EscalationRules = .relaxed) -> LessonEngine {
        var e = LessonEngine(page: page, rules: rules)
        e.handle(.continueTapped)
        e.handle(.notePlayed(pitch: 60))
        XCTAssertEqual(e.blockIndex, 2)
        return e
    }

    func testWalksThroughAPage() {
        var e = LessonEngine(page: page)
        XCTAssertEqual(e.currentBlock?.kind, .explain)

        XCTAssertEqual(e.handle(.notePlayed(pitch: 60)), [], "the first explain block has no advanceOn")
        XCTAssertEqual(e.handle(.continueTapped), [.advanced(to: 1)])

        XCTAssertEqual(e.handle(.continueTapped), [], "advanceOn blocks need the note, not Continue")
        XCTAssertEqual(e.handle(.notePlayed(pitch: 62)), [], "a wrong note doesn't advance")
        XCTAssertEqual(e.handle(.notePlayed(pitch: 60)), [.advanced(to: 2)])

        XCTAssertEqual(e.handle(.listenFinished), [], "only listen blocks react to listenFinished")
        XCTAssertEqual(e.handle(.graded(BlockResult(passed: true))), [.advanced(to: 3)])

        XCTAssertEqual(e.handle(.listenFinished), [.advanced(to: 4)])

        let effects = e.handle(.graded(BlockResult(passed: true, stars: 2)))
        XCTAssertEqual(effects, [.pageComplete(PageResult(stars: 2, blockStars: [4: 2], flaggedBlocks: []))])
        XCTAssertTrue(e.isComplete)
        XCTAssertNil(e.currentBlock)
        XCTAssertEqual(e.handle(.continueTapped), [], "a finished page ignores events")
    }

    func testListenCanBeContinuedEarly() {
        var e = atWaitBlock()
        e.handle(.graded(BlockResult(passed: true)))
        XCTAssertEqual(e.handle(.continueTapped), [.advanced(to: 4)])
    }

    func testWrongNotesOnOneChordRaiseHints() {
        var e = atWaitBlock()
        XCTAssertEqual(e.handle(.wrongNote(chord: 0)), [])
        XCTAssertEqual(e.handle(.wrongNote(chord: 0)), [.hint(.hint)], "2 misses → inline hint")
        XCTAssertEqual(e.handle(.wrongNote(chord: 0)), [.hint(.teacher)], "3 misses → teacher")
        XCTAssertEqual(e.handle(.wrongNote(chord: 0)), [], "no repeat while the level holds")
        XCTAssertEqual(e.handle(.chordPlayed(chord: 0)), [.hint(.none)], "playing it clears the hint")
        XCTAssertEqual(e.missesOnChord, 0)
    }

    func testMissesCountPerChord() {
        var e = atWaitBlock()
        e.handle(.wrongNote(chord: 0))
        XCTAssertEqual(e.handle(.wrongNote(chord: 1)), [], "a new chord starts counting again")
        XCTAssertEqual(e.missesOnChord, 1)
        XCTAssertEqual(e.handle(.chordPlayed(chord: 0)), [], "an old chord doesn't reset the current count")
        XCTAssertEqual(e.missesOnChord, 1)
    }

    func testFailedAttemptsEscalateAndRetry() {
        var e = atWaitBlock()
        XCTAssertEqual(e.handle(.graded(BlockResult(passed: false))), [.retry(attempt: 2)])
        XCTAssertEqual(e.handle(.graded(BlockResult(passed: false))), [.hint(.hint), .retry(attempt: 3)])
        XCTAssertEqual(e.handle(.graded(BlockResult(passed: false))), [.hint(.teacher), .retry(attempt: 4)])
        XCTAssertEqual(e.failedAttempts, 3)
        XCTAssertEqual(e.handle(.graded(BlockResult(passed: true))), [.advanced(to: 3)])
        XCTAssertEqual(e.failedAttempts, 0)
        XCTAssertEqual(e.hintLevel, .none)
    }

    func testRestartKeepsAttemptsButClearsMisses() {
        var e = atWaitBlock()
        e.handle(.graded(BlockResult(passed: false)))
        e.handle(.graded(BlockResult(passed: false)))
        XCTAssertEqual(e.hintLevel, .hint)
        e.handle(.wrongNote(chord: 0))
        e.handle(.wrongNote(chord: 0))
        e.handle(.wrongNote(chord: 0))
        XCTAssertEqual(e.hintLevel, .teacher)
        XCTAssertEqual(e.handle(.restart), [.hint(.hint)], "misses go, attempts stay")
        XCTAssertEqual(e.failedAttempts, 2)
    }

    func testStarredBlockNeedsRequiredStars() {
        var e = LessonEngine(page: page, rules: .strict, startAt: 4)
        XCTAssertEqual(e.handle(.graded(BlockResult(passed: true, stars: 1))), [.retry(attempt: 2)],
                       "Kriti wants two stars")
        let effects = e.handle(.graded(BlockResult(passed: true, stars: 2)))
        XCTAssertEqual(effects, [.pageComplete(PageResult(stars: 2, blockStars: [4: 2], flaggedBlocks: []))])
    }

    func testBestStarsAreKept() {
        var e = LessonEngine(page: page, rules: .strict, startAt: 4)
        e.handle(.graded(BlockResult(passed: false, stars: 1)))
        e.handle(.graded(BlockResult(passed: false, stars: 0)))
        XCTAssertEqual(e.stars(forBlock: 4), 1)
    }

    func testMovingOnFlagsTheBlockAndKeepsItsStars() {
        var e = LessonEngine(page: page, rules: .strict, startAt: 4)
        e.handle(.graded(BlockResult(passed: true, stars: 1)))
        let effects = e.handle(.askToMoveOn)
        XCTAssertEqual(effects, [.pageComplete(PageResult(stars: 1, blockStars: [4: 1], flaggedBlocks: [4]))])
    }

    func testSkippingWithoutStarsScoresZero() {
        var e = atWaitBlock()
        XCTAssertEqual(e.handle(.skip), [.advanced(to: 3)])
        e.handle(.listenFinished)
        let effects = e.handle(.skip)
        XCTAssertEqual(effects, [.pageComplete(PageResult(stars: 0, blockStars: [:], flaggedBlocks: [2, 4]))])
    }

    func testPageWithoutStarredBlocks() {
        let card = LessonPage(id: "p3", title: "Finger numbers", blocks: [
            .concept(.init(card: "fingerNumbers", text: "1 is your thumb", check: NoteName(pitch: 64))),
        ])
        var e = LessonEngine(page: card)
        XCTAssertEqual(e.handle(.continueTapped), [], "a concept check needs the note")
        XCTAssertEqual(e.handle(.notePlayed(pitch: 64)),
                       [.pageComplete(PageResult(stars: nil, blockStars: [:], flaggedBlocks: []))])
    }

    func testNonGradedBlocksIgnoreGradeEvents() {
        var e = LessonEngine(page: page)
        XCTAssertEqual(e.handle(.graded(BlockResult(passed: true))), [])
        XCTAssertEqual(e.handle(.wrongNote(chord: 0)), [])
        XCTAssertEqual(e.blockIndex, 0)
    }

    func testResumeClampsTheStartBlock() {
        XCTAssertEqual(LessonEngine(page: page, startAt: 3).blockIndex, 3)
        XCTAssertEqual(LessonEngine(page: page, startAt: 99).blockIndex, 4)
        XCTAssertEqual(LessonEngine(page: page, startAt: -2).blockIndex, 0)
    }

    func testEmptyPageIsAlreadyComplete() {
        let e = LessonEngine(page: LessonPage(id: "x", title: "x", blocks: []))
        XCTAssertTrue(e.isComplete)
        XCTAssertNil(e.currentBlock)
    }
}
