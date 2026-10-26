import Foundation

/// How much help the page is offering on the current block.
public enum HintLevel: Int, Comparable, Sendable {
    /// Nothing extra.
    case none
    /// An inline hint ("D is the white key just right of C, finger 2").
    case hint
    /// The teacher persona steps in (Alex slows down; Kriti loops the bar).
    case teacher

    public static func < (a: HintLevel, b: HintLevel) -> Bool { a.rawValue < b.rawValue }
}

/// When hints and the teacher appear, and what counts as passing. Personas set these
/// (M7); the defaults are Alex's.
public struct EscalationRules: Equatable, Sendable {
    /// Misses on one chord in wait mode, or failed graded attempts, before the inline hint.
    public var hintAfter: Int
    /// …and before the teacher steps in.
    public var teacherAfter: Int
    /// Stars a starred block needs to count as passed.
    public var requiredStars: Int

    public init(hintAfter: Int = 2, teacherAfter: Int = 3, requiredStars: Int = 1) {
        self.hintAfter = hintAfter
        self.teacherAfter = teacherAfter
        self.requiredStars = requiredStars
    }

    public static let relaxed = EscalationRules()
    public static let strict = EscalationRules(hintAfter: 2, teacherAfter: 3, requiredStars: 2)

    func level(after count: Int) -> HintLevel {
        if count >= teacherAfter { return .teacher }
        if count >= hintAfter { return .hint }
        return .none
    }
}

/// The outcome of one graded run of a block, worked out by the app from the grade report.
public struct BlockResult: Equatable, Sendable {
    public var passed: Bool
    /// 0–3 for blocks that award stars; nil otherwise.
    public var stars: Int?

    public init(passed: Bool, stars: Int? = nil) {
        self.passed = passed
        self.stars = stars
    }
}

/// What happened while the learner played a page.
public enum LessonEvent: Equatable, Sendable {
    /// Any note was played (explain and concept blocks move on when it's the right one).
    case notePlayed(pitch: Int)
    /// Wait mode: a wrong key while waiting on chord `chord` (index in the passage).
    case wrongNote(chord: Int)
    /// Wait mode: chord `chord` was played correctly.
    case chordPlayed(chord: Int)
    /// A listen block finished playing.
    case listenFinished
    /// The Continue button.
    case continueTapped
    /// A graded block's take was graded.
    case graded(BlockResult)
    /// Restart the current block. Attempts so far still count.
    case restart
    /// Skip the block. It's flagged and keeps whatever stars it already earned.
    case skip
    /// The persona escape: the learner asks to move on. Flagged like a skip.
    case askToMoveOn
}

/// What the app should do in response.
public enum LessonEffect: Equatable, Sendable {
    /// Show block `to` (a fresh start: no misses, no hint).
    case advanced(to: Int)
    case hint(HintLevel)
    /// The graded run didn't pass; play the block again. `attempt` is the next attempt's number.
    case retry(attempt: Int)
    case pageComplete(PageResult)
}

public struct PageResult: Equatable, Sendable {
    /// The lowest best-stars across starred blocks (a block skipped before earning any counts 0);
    /// nil for pages without starred blocks.
    public var stars: Int?
    /// Best stars per starred block index.
    public var blockStars: [Int: Int]
    /// Blocks skipped or moved on from without passing.
    public var flaggedBlocks: [Int]

    public init(stars: Int?, blockStars: [Int: Int], flaggedBlocks: [Int]) {
        self.stars = stars
        self.blockStars = blockStars
        self.flaggedBlocks = flaggedBlocks
    }
}

/// Plays one lesson page: which block is current, attempts, hints and the result.
/// A pure state machine with no audio or UI; `LessonRunner` (M3) feeds it events from
/// `PlaySession` and acts on the effects.
public struct LessonEngine: Sendable {
    public let page: LessonPage
    public var rules: EscalationRules

    public private(set) var blockIndex: Int
    /// Graded runs of the current block that didn't pass.
    public private(set) var failedAttempts = 0
    /// Wrong notes on the chord the guide is waiting on.
    public private(set) var missesOnChord = 0
    public private(set) var hintLevel: HintLevel = .none
    public private(set) var result: PageResult?

    private var missChord: Int?
    private var bestStars: [Int: Int] = [:]
    private var flagged: Set<Int> = []

    /// `startAt` resumes a page part-way (the saved block); out-of-range values clamp.
    public init(page: LessonPage, rules: EscalationRules = .relaxed, startAt: Int = 0) {
        self.page = page
        self.rules = rules
        self.blockIndex = min(max(0, startAt), max(0, page.blocks.count - 1))
        if page.blocks.isEmpty { result = PageResult(stars: nil, blockStars: [:], flaggedBlocks: []) }
    }

    public var isComplete: Bool { result != nil }

    public var currentBlock: Block? {
        isComplete || !page.blocks.indices.contains(blockIndex) ? nil : page.blocks[blockIndex]
    }

    /// Best stars so far on a starred block.
    public func stars(forBlock index: Int) -> Int? { bestStars[index] }

    @discardableResult
    public mutating func handle(_ event: LessonEvent) -> [LessonEffect] {
        guard let block = currentBlock else { return [] }
        switch event {
        case .notePlayed(let pitch):
            switch block {
            case .explain(let b) where b.advanceOn?.pitch == pitch: return advance()
            case .concept(let b) where b.check?.pitch == pitch: return advance()
            default: return []
            }

        case .wrongNote(let chord):
            guard block.isGraded else { return [] }
            if missChord != chord {
                missChord = chord
                missesOnChord = 0
            }
            missesOnChord += 1
            return updateHint()

        case .chordPlayed(let chord):
            guard block.isGraded, chord == missChord else { return [] }
            missChord = nil
            missesOnChord = 0
            return updateHint()

        case .listenFinished:
            if case .listen = block { return advance() }
            return []

        case .continueTapped:
            switch block {
            case .explain(let b) where b.advanceOn == nil: return advance()
            case .concept(let b) where b.check == nil: return advance()
            case .listen: return advance()
            default: return []
            }

        case .graded(let r):
            guard block.isGraded else { return [] }
            if let stars = r.stars, block.awardsStars {
                bestStars[blockIndex] = max(bestStars[blockIndex] ?? 0, stars)
            }
            let passed = r.passed && (r.stars.map { $0 >= rules.requiredStars } ?? true)
            if passed { return advance() }
            failedAttempts += 1
            missChord = nil
            missesOnChord = 0
            return updateHint() + [.retry(attempt: failedAttempts + 1)]

        case .restart:
            missChord = nil
            missesOnChord = 0
            return updateHint()

        case .skip, .askToMoveOn:
            flagged.insert(blockIndex)
            return advance()
        }
    }

    // MARK: Private

    private mutating func updateHint() -> [LessonEffect] {
        let level = max(rules.level(after: missesOnChord), rules.level(after: failedAttempts))
        guard level != hintLevel else { return [] }
        hintLevel = level
        return [.hint(level)]
    }

    private mutating func advance() -> [LessonEffect] {
        failedAttempts = 0
        missesOnChord = 0
        missChord = nil
        hintLevel = .none
        blockIndex += 1
        guard blockIndex >= page.blocks.count else { return [.advanced(to: blockIndex)] }
        let starred = page.starredBlocks
        let stars = starred.isEmpty ? nil : starred.map { bestStars[$0] ?? 0 }.min()
        let done = PageResult(stars: stars, blockStars: bestStars, flaggedBlocks: flagged.sorted())
        result = done
        return [.pageComplete(done)]
    }
}
