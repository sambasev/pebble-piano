import Foundation
import PianoGraderCore

// The lesson file format. A unit is a folder holding `unit.json` and the MIDI files its
// blocks name (paths are relative to that folder):
//
// {
//   "id": "u1", "title": "Middle C position",
//   "pages": [
//     { "id": "p2", "title": "Meet D", "newNotes": ["D4"], "unlocks": "p3",
//       "blocks": [
//         { "type": "explain", "text": "D is the white key between the 2 black keys",
//           "highlight": ["D4"], "advanceOn": "D4" },
//         { "type": "wait", "midi": "p2-ex1.mid", "fingering": [2, 2, 2], "hand": "R" },
//         { "type": "listen", "midi": "p2-ex3.mid", "tempo": 60 },
//         { "type": "timed", "midi": "p2-ex3.mid", "tempo": 60, "countInBeats": 4 }
//       ] } ]
// }
//
// See docs/design/beginner-journeys.md ("A lesson is data").

/// A unit of a book: an ordered list of lesson pages, usually ending with a goal song.
public struct LessonUnit: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var pages: [LessonPage]
    /// Every page is open from the start (the learner's own pieces), not unlocked in order.
    public var allPagesOpen: Bool?

    public init(id: String, title: String, pages: [LessonPage], allPagesOpen: Bool? = nil) {
        self.id = id
        self.title = title
        self.pages = pages
        self.allPagesOpen = allPagesOpen
    }

    public func page(_ id: String) -> LessonPage? { pages.first { $0.id == id } }

    public func index(of pageID: String) -> Int? { pages.firstIndex { $0.id == pageID } }

    /// The first page is always open; any other page opens when a completed page unlocks it.
    public func isUnlocked(_ pageID: String, completed: Set<String>) -> Bool {
        guard let first = pages.first else { return false }
        if first.id == pageID { return true }
        if allPagesOpen == true { return page(pageID) != nil }
        return pages.contains { completed.contains($0.id) && $0.unlocks == pageID }
    }

    /// The first unlocked page not yet completed, in unit order; nil when every page is done.
    public func nextPage(completed: Set<String>) -> LessonPage? {
        pages.first { !completed.contains($0.id) && isUnlocked($0.id, completed: completed) }
    }
}

/// One page of the eBook: a vertical sequence of blocks the learner works through in order.
public struct LessonPage: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// Notes this page introduces (for the unit map and the session summary).
    public var newNotes: [NoteName]
    public var blocks: [Block]
    /// The page completing this one opens.
    public var unlocks: String?
    /// The inline hint after a couple of misses ("D is the white key between the 2 black
    /// keys"), unless the block gives its own.
    public var hint: String?

    public init(id: String, title: String, newNotes: [NoteName] = [], blocks: [Block], unlocks: String? = nil,
                hint: String? = nil) {
        self.id = id
        self.title = title
        self.newNotes = newNotes
        self.blocks = blocks
        self.unlocks = unlocks
        self.hint = hint
    }

    private enum CodingKeys: String, CodingKey { case id, title, newNotes, blocks, unlocks, hint }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        newNotes = try c.decodeIfPresent([NoteName].self, forKey: .newNotes) ?? []
        blocks = try c.decode([Block].self, forKey: .blocks)
        unlocks = try c.decodeIfPresent(String.self, forKey: .unlocks)
        hint = try c.decodeIfPresent(String.self, forKey: .hint)
    }

    /// The hint for block `index`: its own, else the page's.
    public func hint(forBlock index: Int) -> String? {
        guard blocks.indices.contains(index) else { return hint }
        return blocks[index].hint ?? hint
    }

    /// The music that stands for the page when previewing it from the map: its song, else its
    /// last listening, timed or wait exercise (the fullest version of what it teaches). Nil for
    /// pages with nothing to play (ear training, explanations).
    public var previewBlock: Block? {
        for kind in [Block.Kind.songChallenge, .listen, .timed, .wait] {
            if let block = blocks.last(where: { $0.kind == kind }) { return block }
        }
        return nil
    }

    /// The page that plays the learner's own goal song (shown as the unit's finale).
    public var isGoalSongPage: Bool {
        blocks.contains { if case .songChallenge(let b) = $0 { return b.useGoalSong } else { return false } }
    }

    /// A song page along the way (not the goal song): a checkpoint for the notes so far.
    public var isCheckpointSong: Bool {
        !isGoalSongPage && blocks.contains { $0.kind == .songChallenge }
    }

    /// Indices of the blocks that award stars (timed and song challenge). The page's stars
    /// are the lowest of theirs.
    public var starredBlocks: [Int] {
        blocks.indices.filter { blocks[$0].awardsStars }
    }
}


/// One step on a lesson page.
public enum Block: Equatable, Sendable {
    /// Text plus highlighted keys. Moves on when `advanceOn` is played, or on Continue.
    case explain(Explain)
    /// A concept card (finger numbers, …), with an optional note to play as a check.
    case concept(Concept)
    /// The playhead waits on each chord until it's played (`WaitGuide`).
    case wait(Exercise)
    /// The app plays the passage with keys lit.
    case listen(Listen)
    /// Count-in, then a moving playhead over clicks; graded.
    case timed(Timed)
    /// The unit's goal song: listen, learn, practise, perform. Stages arrive with M6.
    case songChallenge(SongChallenge)
    case earTraining(EarTraining)

    public struct EarTraining: Codable, Equatable, Sendable {
        public var level: Int
        public var stage: Int
        public var questions: Int
        public var passAccuracy: Double
        public var notes: [Int]?
        public init(level: Int, stage: Int, questions: Int = 5, passAccuracy: Double = 0.8, notes: [Int]? = nil) {
            self.level = level; self.stage = stage; self.questions = questions
            self.passAccuracy = passAccuracy; self.notes = notes
        }
        public var stageID: EarStageID { EarStageID(level: level, stage: stage) }
        private enum CodingKeys: String, CodingKey { case level, stage, questions, passAccuracy, notes }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            level = try c.decode(Int.self, forKey: .level)
            stage = try c.decode(Int.self, forKey: .stage)
            questions = try c.decodeIfPresent(Int.self, forKey: .questions) ?? 5
            passAccuracy = try c.decodeIfPresent(Double.self, forKey: .passAccuracy) ?? 0.8
            notes = try c.decodeIfPresent([Int].self, forKey: .notes)
        }
    }

    public struct Explain: Codable, Equatable, Sendable {
        public var text: String
        public var highlight: [NoteName]
        public var advanceOn: NoteName?

        public init(text: String, highlight: [NoteName] = [], advanceOn: NoteName? = nil) {
            self.text = text
            self.highlight = highlight
            self.advanceOn = advanceOn
        }

        private enum CodingKeys: String, CodingKey { case text, highlight, advanceOn }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            text = try c.decode(String.self, forKey: .text)
            highlight = try c.decodeIfPresent([NoteName].self, forKey: .highlight) ?? []
            advanceOn = try c.decodeIfPresent(NoteName.self, forKey: .advanceOn)
        }
    }

    public struct Concept: Codable, Equatable, Sendable {
        /// Which card to draw, e.g. "fingerNumbers".
        public var card: String
        public var text: String
        /// "Play the note under finger 3": the note that shows it was understood.
        public var check: NoteName?

        public init(card: String, text: String, check: NoteName? = nil) {
            self.card = card
            self.text = text
            self.check = check
        }
    }

    public struct Exercise: Codable, Equatable, Sendable {
        public var midi: String
        /// Shown above the block, e.g. "Play the note C".
        public var prompt: String?
        /// One finger number (1–5) per note, in score order.
        public var fingering: [Int]?
        public var hand: Hand?
        public var hint: String?

        public init(midi: String, prompt: String? = nil, fingering: [Int]? = nil, hand: Hand? = nil, hint: String? = nil) {
            self.midi = midi
            self.prompt = prompt
            self.fingering = fingering
            self.hand = hand
            self.hint = hint
        }
    }

    public struct Listen: Codable, Equatable, Sendable {
        public var midi: String
        public var prompt: String?
        /// Quarter notes per minute; nil plays at the file's tempo.
        public var tempo: Double?

        public init(midi: String, prompt: String? = nil, tempo: Double? = nil) {
            self.midi = midi
            self.prompt = prompt
            self.tempo = tempo
        }
    }

    public struct Timed: Codable, Equatable, Sendable {
        public var midi: String
        public var prompt: String?
        public var tempo: Double
        public var countInBeats: Int
        /// A rubric name ("beginner", "intermediate") or a path relative to the unit folder.
        public var rubric: String
        public var fingering: [Int]?
        public var hand: Hand?
        public var hint: String?

        public init(midi: String, prompt: String? = nil, tempo: Double, countInBeats: Int = 4,
                    rubric: String = "beginner", fingering: [Int]? = nil, hand: Hand? = nil, hint: String? = nil) {
            self.midi = midi
            self.prompt = prompt
            self.tempo = tempo
            self.countInBeats = countInBeats
            self.rubric = rubric
            self.fingering = fingering
            self.hand = hand
            self.hint = hint
        }

        private enum CodingKeys: String, CodingKey { case midi, prompt, tempo, countInBeats, rubric, fingering, hand, hint }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            midi = try c.decode(String.self, forKey: .midi)
            prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
            tempo = try c.decode(Double.self, forKey: .tempo)
            countInBeats = try c.decodeIfPresent(Int.self, forKey: .countInBeats) ?? 4
            rubric = try c.decodeIfPresent(String.self, forKey: .rubric) ?? "beginner"
            fingering = try c.decodeIfPresent([Int].self, forKey: .fingering)
            hand = try c.decodeIfPresent(Hand.self, forKey: .hand)
            hint = try c.decodeIfPresent(String.self, forKey: .hint)
        }
    }

    public struct SongChallenge: Codable, Equatable, Sendable {
        public var midi: String
        public var title: String
        /// The backing track linked to this song, by its name in the Backing Tracks library.
        public var backing: String?
        /// Tempo factors for the Practise stage, slowest first.
        public var practiceTempos: [Double]
        public var fingering: [Int]?
        /// Play the learner's own goal song (`songs/<GoalSong id>.mid` in the unit folder)
        /// instead of `midi`, which stays the fallback.
        public var useGoalSong: Bool

        public init(midi: String, title: String, backing: String? = nil, practiceTempos: [Double] = [0.7],
                    fingering: [Int]? = nil, useGoalSong: Bool = false) {
            self.midi = midi
            self.title = title
            self.backing = backing
            self.practiceTempos = practiceTempos
            self.fingering = fingering
            self.useGoalSong = useGoalSong
        }

        /// The goal song's file in a unit folder.
        public static func goalSongPath(_ id: String) -> String { "songs/\(id).mid" }

        private enum CodingKeys: String, CodingKey { case midi, title, backing, practiceTempos, fingering, useGoalSong }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            midi = try c.decode(String.self, forKey: .midi)
            title = try c.decode(String.self, forKey: .title)
            backing = try c.decodeIfPresent(String.self, forKey: .backing)
            practiceTempos = try c.decodeIfPresent([Double].self, forKey: .practiceTempos) ?? [0.7]
            fingering = try c.decodeIfPresent([Int].self, forKey: .fingering)
            useGoalSong = try c.decodeIfPresent(Bool.self, forKey: .useGoalSong) ?? false
        }
    }

    /// The `type` value in the file.
    public var kind: Kind {
        switch self {
        case .explain: return .explain
        case .concept: return .concept
        case .wait: return .wait
        case .listen: return .listen
        case .timed: return .timed
        case .songChallenge: return .songChallenge
        case .earTraining: return .earTraining
        }
    }

    public enum Kind: String, Codable, Sendable {
        case explain, concept, wait, listen, timed, songChallenge, earTraining
    }

    /// The MIDI file the block plays or grades against, if any.
    public var midi: String? {
        switch self {
        case .explain, .concept, .earTraining: return nil
        case .wait(let b): return b.midi
        case .listen(let b): return b.midi
        case .timed(let b): return b.midi
        case .songChallenge(let b): return b.midi
        }
    }

    /// The block's own hint, if it gives one.
    public var hint: String? {
        switch self {
        case .wait(let b): return b.hint
        case .timed(let b): return b.hint
        default: return nil
        }
    }

    public var fingering: [Int]? {
        switch self {
        case .wait(let b): return b.fingering
        case .timed(let b): return b.fingering
        case .songChallenge(let b): return b.fingering
        default: return nil
        }
    }

    /// Blocks whose result is a grade report (and so count attempts).
    public var isGraded: Bool {
        switch self {
        case .wait, .timed, .songChallenge, .earTraining: return true
        default: return false
        }
    }

    public var awardsStars: Bool {
        switch self {
        case .timed, .songChallenge: return true
        default: return false
        }
    }
}

extension Block: Codable {
    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TypeKey.self)
        switch try c.decode(Kind.self, forKey: .type) {
        case .explain: self = .explain(try Explain(from: decoder))
        case .concept: self = .concept(try Concept(from: decoder))
        case .wait: self = .wait(try Exercise(from: decoder))
        case .listen: self = .listen(try Listen(from: decoder))
        case .timed: self = .timed(try Timed(from: decoder))
        case .songChallenge: self = .songChallenge(try SongChallenge(from: decoder))
        case .earTraining: self = .earTraining(try EarTraining(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .explain(let b): try b.encode(to: encoder)
        case .concept(let b): try b.encode(to: encoder)
        case .wait(let b): try b.encode(to: encoder)
        case .listen(let b): try b.encode(to: encoder)
        case .timed(let b): try b.encode(to: encoder)
        case .songChallenge(let b): try b.encode(to: encoder)
        case .earTraining(let b): try b.encode(to: encoder)
        }
        var c = encoder.container(keyedBy: TypeKey.self)
        try c.encode(kind, forKey: .type)
    }
}
