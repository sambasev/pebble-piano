import Foundation

/// A graded timed block and how it went: what the next session's warm-up replays.
public struct TimedBlockResult: Codable, Equatable, Sendable {
    public var unit: String
    public var page: String
    /// Block index on the page, from 0.
    public var block: Int
    /// The grader's note score, 0–1.
    public var notes: Double

    public init(unit: String, page: String, block: Int, notes: Double) {
        self.unit = unit
        self.page = page
        self.block = block
        self.notes = notes
    }
}

/// A completed ear quiz, kept independently of lesson pages and stars.
public struct EarQuizSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var level: Int
    public var stage: Int
    public var correct: Int
    public var total: Int
    public init(id: String, level: Int, stage: Int, correct: Int, total: Int) {
        self.id = id; self.level = level; self.stage = stage; self.correct = correct; self.total = total
    }
}

/// One sitting in Learn or Ear Training. Older records are lesson sessions.
public struct PracticeSession: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case lesson, earTraining }
    public var id: UUID
    public var started: Date
    /// The last activity (idle time after it isn't counted).
    public var ended: Date
    /// Pages opened, in order (IDs, no repeats).
    public var pages: [String]
    /// Pages finished, in order (IDs, no repeats).
    public var completedPages: [String]
    /// New notes from pages finished for the first time ("C", "D").
    public var notesLearned: [String]
    /// Stars earned on finished pages.
    public var stars: Int
    /// The last timed block graded.
    public var lastTimed: TimedBlockResult?
    public var kind: Kind
    /// Ear practice counts foreground activity, excluding idle gaps; older sessions use wall time.
    public var activeSeconds: Double?
    public var earQuestionsAnswered: Int
    public var earQuizzes: [EarQuizSummary]

    public init(id: UUID = UUID(), started: Date, ended: Date? = nil, pages: [String] = [], completedPages: [String] = [],
                notesLearned: [String] = [], stars: Int = 0, lastTimed: TimedBlockResult? = nil,
                kind: Kind = .lesson, activeSeconds: Double? = nil,
                earQuestionsAnswered: Int = 0, earQuizzes: [EarQuizSummary] = []) {
        self.id = id
        self.started = started
        self.ended = ended ?? started
        self.pages = pages
        self.completedPages = completedPages
        self.notesLearned = notesLearned
        self.stars = stars
        self.lastTimed = lastTimed
        self.kind = kind
        self.activeSeconds = activeSeconds
        self.earQuestionsAnswered = earQuestionsAnswered
        self.earQuizzes = earQuizzes
    }

    /// Whole minutes, at least 1.
    public var minutes: Int { max(1, Int(((activeSeconds ?? ended.timeIntervalSince(started)) / 60).rounded())) }

    private enum CodingKeys: String, CodingKey {
        case id, started, ended, pages, completedPages, notesLearned, stars, lastTimed
        case kind, activeSeconds, earQuestionsAnswered, earQuizzes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        started = try c.decode(Date.self, forKey: .started)
        ended = try c.decodeIfPresent(Date.self, forKey: .ended) ?? started
        pages = try c.decodeIfPresent([String].self, forKey: .pages) ?? []
        completedPages = try c.decodeIfPresent([String].self, forKey: .completedPages) ?? []
        notesLearned = try c.decodeIfPresent([String].self, forKey: .notesLearned) ?? []
        stars = try c.decodeIfPresent(Int.self, forKey: .stars) ?? 0
        lastTimed = try c.decodeIfPresent(TimedBlockResult.self, forKey: .lastTimed)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .lesson
        activeSeconds = try c.decodeIfPresent(Double.self, forKey: .activeSeconds)
        earQuestionsAnswered = try c.decodeIfPresent(Int.self, forKey: .earQuestionsAnswered) ?? 0
        earQuizzes = try c.decodeIfPresent([EarQuizSummary].self, forKey: .earQuizzes) ?? []
    }
}

/// Shared daily totals, including both lesson and ear sessions. Checkpoints replace by ID.
public enum PracticeTotals {
    public static func unique(_ sessions: [PracticeSession]) -> [PracticeSession] {
        var unique: [UUID: PracticeSession] = [:]
        for session in sessions { unique[session.id] = session }
        return unique.values.sorted { $0.started < $1.started }
    }
    public static func today(_ sessions: [PracticeSession], now: Date = Date(), calendar: Calendar = .current) -> [PracticeSession] {
        unique(sessions).filter { calendar.isDate($0.started, inSameDayAs: now) }
    }
}

/// The weekly streak: days practised this week. A missed day costs nothing.
public enum WeeklyStreak {
    /// Distinct days in the calendar week containing `now` with a session that started then.
    public static func daysThisWeek(_ sessions: [PracticeSession], now: Date = Date(),
                                    calendar: Calendar = .current) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        let days = sessions
            .filter { week.contains($0.started) }
            .map { calendar.startOfDay(for: $0.started) }
        return Set(days).count
    }

    /// Minutes practised in the calendar week containing `now` (each session's own minutes).
    public static func minutesThisWeek(_ sessions: [PracticeSession], now: Date = Date(),
                                       calendar: Calendar = .current) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return PracticeTotals.unique(sessions).filter { week.contains($0.started) }.reduce(0) { $0 + $1.minutes }
    }

    /// "3 days this week", "1 day this week".
    public static func label(days: Int) -> String {
        "\(days) day\(days == 1 ? "" : "s") this week"
    }
}

/// `<learner folder>/sessions.json`: past sessions, oldest first (the most recent 500).
extension LearnerHistory {
    var sessionsURL: URL { folder.appendingPathComponent("sessions.json") }

    static let sessionsKept = 500

    /// Missing or unreadable → empty.
    public func sessions() -> [PracticeSession] {
        guard let data = try? Data(contentsOf: sessionsURL),
              let all = try? Self.jsonDecoder().decode([PracticeSession].self, from: data) else { return [] }
        return all
    }

    /// Adds a finished session, or replaces the one with the same ID.
    public func recordSession(_ session: PracticeSession) throws {
        var all = sessions()
        if let i = all.firstIndex(where: { $0.id == session.id }) {
            all[i] = session
        } else {
            all.append(session)
        }
        all.sort { $0.started < $1.started }
        if all.count > Self.sessionsKept { all.removeFirst(all.count - Self.sessionsKept) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(all).write(to: sessionsURL, options: .atomic)
    }

    /// The most recent session's last timed block (searching back past sessions without one).
    public func lastTimedBlock() -> TimedBlockResult? {
        sessions().reversed().lazy.compactMap(\.lastTimed).first
    }
}
