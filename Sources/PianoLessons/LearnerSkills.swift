import Foundation
import PianoGraderCore

// What a learner has shown they can do, what a piece asks of them, and the gap between the
// two: which stock lessons to suggest first and which lesson steps they can skip. Worked out
// from what the app already saves (Unit 1 progress, pieces passed with the tutor or in Learn);
// nothing here is stored. The grader's evidence decides; the model is only told about it.

/// A piece the learner has passed: the tutor's Perform with 2★ or more, or its Learn page
/// completed.
public struct PassedPiece: Sendable {
    public var title: String
    public var sequence: MIDISequence
    public var stars: Int?

    public init(title: String, sequence: MIDISequence, stars: Int? = nil) {
        self.title = title
        self.sequence = sequence
        self.stars = stars
    }
}

/// A lesson under way, for the model's picture of the learner.
public struct PieceUnderWay: Sendable {
    public var title: String
    public var step: String
    public init(title: String, step: String) { self.title = title; self.step = step }
}

public struct LearnerSkills: Equatable, Sendable {
    public var notesRight: Set<Int> = []
    public var notesLeft: Set<Int> = []
    public var knowsFingerNumbers = false
    public var playedLeftHand = false
    public var playedBassClef = false
    public var playedHandsTogether = false
    /// The fastest tempo (quarters a minute) passed in time: a Unit 1 timed block, or a passed piece.
    public var fastestTempo: Double?
    /// Unit 1 pages completed.
    public var completedPages: Set<String> = []
    /// Titles of pieces passed, and lessons under way ("Mary: Phrase 2, slowly").
    public var passedTitles: [String] = []
    public var underWay: [String] = []

    public init() {}

    public static let none = LearnerSkills()

    public var knownNotes: Set<Int> { notesRight.union(notesLeft) }

    /// Builds the picture from Unit 1 (its pages, and which are completed) and the pieces passed.
    public static func from(unit: LessonUnit?, completedPages: Set<String>, passed: [PassedPiece],
                            underWay: [PieceUnderWay] = []) -> LearnerSkills {
        var s = LearnerSkills()
        s.completedPages = completedPages
        for page in unit?.pages ?? [] where completedPages.contains(page.id) {
            s.notesRight.formUnion(page.newNotes.map(\.pitch))
            for block in page.blocks {
                if case .concept(let c) = block, c.card == "fingerNumbers" { s.knowsFingerNumbers = true }
                if case .timed(let t) = block { s.fastestTempo = max(s.fastestTempo ?? 0, t.tempo) }
                if case .wait(let w) = block, w.hand == .left { s.playedLeftHand = true }
            }
        }
        for piece in passed {
            let seq = piece.sequence
            if seq.hasTwoHands {
                s.notesRight.formUnion(seq.hand(.right).notes.map(\.pitch))
                let left = seq.hand(.left).notes.map(\.pitch)
                s.notesLeft.formUnion(left)
                s.playedLeftHand = true
                s.playedHandsTogether = true
                if !left.isEmpty, Double(left.reduce(0, +)) / Double(left.count) < 57 { s.playedBassClef = true }
            } else {
                s.notesRight.formUnion(seq.notes.map(\.pitch))
            }
            s.fastestTempo = max(s.fastestTempo ?? 0, seq.initialTempoBPM)
            s.passedTitles.append(piece.title)
        }
        s.underWay = underWay.map { "\($0.title) (\($0.step))" }
        return s
    }

    /// A few lines about the learner for the model: notes, hands, tempo, pieces.
    public var summary: String {
        func names(_ notes: Set<Int>) -> String {
            notes.isEmpty ? "none" : notes.sorted().map { NoteName(pitch: $0).name }.joined(separator: " ")
        }
        var lines = ["Right-hand notes met: \(names(notesRight))", "Left-hand notes met: \(names(notesLeft))"]
        lines.append(knowsFingerNumbers ? "Knows finger numbers." : "Hasn't learned finger numbers yet.")
        lines.append(playedHandsTogether ? "Has played both hands together." : playedLeftHand ? "Has played the left hand, not both together." : "Hasn't played with the left hand yet.")
        if let t = fastestTempo { lines.append("Fastest tempo passed: \(Int(t)) beats a minute.") } else { lines.append("Hasn't played in time yet.") }
        if !passedTitles.isEmpty { lines.append("Pieces passed: \(passedTitles.joined(separator: ", ")).") }
        if !underWay.isEmpty { lines.append("Learning now: \(underWay.joined(separator: "; ")).") }
        return lines.joined(separator: "\n")
    }
}

/// What a piece asks of the learner.
public struct PieceRequirements: Equatable, Sendable {
    public var notesRight: Set<Int>
    public var notesLeft: Set<Int>
    public var usesLeftHand: Bool
    public var tempo: Double
    public var hasChords: Bool

    public init(_ sequence: MIDISequence) {
        if sequence.hasTwoHands {
            notesRight = Set(sequence.hand(.right).notes.map(\.pitch))
            notesLeft = Set(sequence.hand(.left).notes.map(\.pitch))
        } else {
            notesRight = Set(sequence.notes.map(\.pitch))
            notesLeft = []
        }
        usesLeftHand = !notesLeft.isEmpty
        tempo = sequence.initialTempoBPM
        let onsets = Dictionary(grouping: sequence.notes) { "\($0.track)-\(Int(($0.onsetBeats * 100).rounded()))" }
        hasChords = onsets.values.contains { $0.count > 1 }
    }
}

/// What to do before a piece, and what can be skipped in it.
public struct Readiness: Equatable, Sendable {
    /// A stock lesson page to do first.
    public struct Suggestion: Equatable, Sendable {
        public var pageID: String
        public var title: String
        /// Why: "teaches G", "finger numbers".
        public var reason: String?
    }

    /// Unit 1 pages to do first, in order (incomplete pages up to the furthest one needed: the
    /// unit opens them one after another).
    public var suggestions: [Suggestion]
    /// The gaps in words, for the card ("you haven't met G yet").
    public var gaps: [String]

    public var isReady: Bool { suggestions.isEmpty }

    public static func check(_ needs: PieceRequirements, skills: LearnerSkills, unit: LessonUnit?) -> Readiness {
        guard let unit else { return Readiness(suggestions: [], gaps: []) }
        var needed: [Int: [String]] = [:]   // page index → reasons
        var gaps: [String] = []
        let notePage: [Int: Int] = Dictionary(unit.pages.enumerated().flatMap { i, p in p.newNotes.map { ($0.pitch, i) } },
                                              uniquingKeysWith: { a, _ in a })
        for pitch in needs.notesRight.sorted() where !skills.notesRight.contains(pitch) {
            guard let i = notePage[pitch], !skills.completedPages.contains(unit.pages[i].id) else { continue }
            let name = NoteName(pitch: pitch).letter
            needed[i, default: []].append("teaches \(name)")
            gaps.append("you haven't met \(name) yet")
        }
        if !skills.knowsFingerNumbers,
           let i = unit.pages.firstIndex(where: { $0.blocks.contains { if case .concept(let c) = $0 { return c.card == "fingerNumbers" }; return false } }),
           !skills.completedPages.contains(unit.pages[i].id) {
            needed[i, default: []].append("finger numbers")
            gaps.append("this piece uses finger numbers")
        }
        guard let furthest = needed.keys.max() else { return Readiness(suggestions: [], gaps: []) }
        let suggestions = unit.pages.enumerated()
            .filter { i, p in i <= furthest && !skills.completedPages.contains(p.id) }
            .map { i, p in Suggestion(pageID: p.id, title: p.title, reason: needed[i]?.joined(separator: ", ")) }
        return Readiness(suggestions: suggestions, gaps: gaps)
    }
}

/// What the learner already has for each phrase of a plan, so steps they don't need are skipped.
public struct Familiarity: Codable, Equatable, Sendable {
    /// Phrases (by index) whose notes, both hands, the learner has all met.
    public var knownPhrases: Set<Int>
    /// They've passed a piece with both hands together.
    public var handsTogether: Bool
    /// They've passed a piece at this piece's tempo or faster.
    public var tempoReached: Bool

    public init(knownPhrases: Set<Int> = [], handsTogether: Bool = false, tempoReached: Bool = false) {
        self.knownPhrases = knownPhrases
        self.handsTogether = handsTogether
        self.tempoReached = tempoReached
    }

    public static func of(_ plan: LessonPlan, sequence: MIDISequence, skills: LearnerSkills) -> Familiarity {
        let qpm = sequence.timeSignature.quartersPerMeasure
        var known: Set<Int> = []
        let right = sequence.hasTwoHands ? sequence.hand(.right) : sequence
        let left = sequence.hasTwoHands ? sequence.hand(.left) : MIDISequence(notes: [])
        for (i, p) in plan.phrases.enumerated() {
            let start = Double(p.bars.lowerBound - 1) * qpm, end = Double(p.bars.upperBound) * qpm
            func inPhrase(_ n: NoteEvent) -> Bool { n.onsetBeats >= start - 1e-6 && n.onsetBeats < end - 1e-6 }
            let r = Set(right.notes.filter(inPhrase).map(\.pitch)), l = Set(left.notes.filter(inPhrase).map(\.pitch))
            if r.isSubset(of: skills.notesRight.union(skills.notesLeft)) && l.isSubset(of: skills.notesLeft.union(skills.notesRight)) {
                known.insert(i)
            }
        }
        return Familiarity(knownPhrases: known, handsTogether: skills.playedHandsTogether,
                           tempoReached: (skills.fastestTempo ?? 0) >= sequence.initialTempoBPM - 0.5)
    }
}
