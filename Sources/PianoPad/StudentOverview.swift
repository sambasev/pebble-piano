#if os(macOS)
import Foundation
import PianoGraderCore
import PianoLessons
import PianoPadState

/// A learner's practice and mistakes over time, built from their saved takes and sessions:
/// what the progress overview charts. Pure, so it can be tested without files.
struct StudentOverview {
    /// One graded take, reduced to what the overview needs.
    struct Take: Equatable {
        var date: Date
        var piece: PieceID
        var score: Double
        var passed: Bool
        var tally: MistakeTally
        /// Signed (fitted − target) ÷ target; nil when the take was too short to fit a tempo.
        var tempoDeviation: Double?
        /// Where each mistake was, by bar, for trouble spots.
        var spots: [Spot]
        /// Played with the AI tutor (in Practice), rather than in Learn or alone.
        var tutored: Bool

        struct Spot: Equatable {
            var category: MistakeTally.Category
            var measure: Int
        }

        init(date: Date, piece: PieceID, score: Double, passed: Bool, tally: MistakeTally,
             tempoDeviation: Double? = nil, spots: [Spot] = [], tutored: Bool = false) {
            self.date = date
            self.piece = piece
            self.score = score
            self.passed = passed
            self.tally = tally
            self.tempoDeviation = tempoDeviation
            self.spots = spots
            self.tutored = tutored
        }

        /// `printedMeasures`: for a tutor drill, the piece's printed bar for each of the drill's bars
        /// (the report counts bars from the start of the drill).
        init(date: Date, piece: PieceID, report: GradeReport, tutored: Bool = false, printedMeasures: [Int]? = nil) {
            let spots = report.flags.compactMap { flag -> Spot? in
                let category: MistakeTally.Category
                switch flag.kind {
                case .wrongPitch: category = .pitch
                case .missed: category = .missed
                case .extra: category = .extra
                case .early, .late: category = .timing
                }
                var measure = flag.position.measure
                if let printed = printedMeasures, printed.indices.contains(measure - 1) { measure = printed[measure - 1] }
                return Spot(category: category, measure: measure)
            }
            self.init(date: date, piece: piece, score: report.notes.score, passed: report.passed,
                      tally: MistakeTally(report), tempoDeviation: report.timing?.tempoDeviation, spots: spots,
                      tutored: tutored)
        }

        var isLesson: Bool { piece.rawValue.hasPrefix("lesson:") }
    }

    enum Range: String, CaseIterable, Identifiable {
        case week, month, quarter, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .week: "7 days"
            case .month: "30 days"
            case .quarter: "90 days"
            case .all: "All time"
            }
        }
        var days: Int? {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 90
            case .all: nil
            }
        }
    }

    /// One bar on the charts: a day, or a week when the range is long.
    struct Bucket: Identifiable, Equatable {
        var start: Date
        var lessonTakes = 0
        var tutorTakes = 0
        var otherTakes = 0
        var tally = MistakeTally()
        var scoreSum = 0.0
        var tempoSum = 0.0
        var tempoCount = 0
        var id: Date { start }
        var takes: Int { lessonTakes + tutorTakes + otherTakes }
        var averageScore: Double? { takes > 0 ? scoreSum / Double(takes) : nil }
        var averageTempoDeviation: Double? { tempoCount > 0 ? tempoSum / Double(tempoCount) : nil }

        /// Mistakes of a kind per 100 notes asked for; tempo is the share of takes (in %) that rushed, dragged or wandered.
        func rate(_ category: MistakeTally.Category) -> Double {
            StudentOverview.rate(category, tally, takes: takes)
        }
    }

    /// Earlier half of the range against the recent half, for one kind of mistake.
    struct Trend: Identifiable, Equatable {
        var category: MistakeTally.Category
        var earlier: Double
        var recent: Double
        var id: String { category.rawValue }
        /// Recent ÷ earlier − 1; nil when there was nothing earlier to compare against.
        var change: Double? { earlier > 0 ? recent / earlier - 1 : nil }
    }

    /// A bar of a piece where mistakes keep happening.
    struct TroubleSpot: Identifiable, Equatable {
        var piece: PieceID
        var measure: Int
        var count: Int
        /// The kind of mistake made most often there.
        var category: MistakeTally.Category
        var id: String { "\(piece.rawValue)#\(measure)" }
    }

    struct PieceSummary: Identifiable, Equatable {
        var piece: PieceID
        var takes: Int
        var bestScore: Double
        var lastScore: Double
        var lastPlayed: Date
        var tally: MistakeTally
        /// Some takes were with the AI tutor.
        var tutored = false
        var id: PieceID { piece }
        /// The note-level mistake made most per 100 notes; nil with none.
        var mainMistake: MistakeTally.Category? {
            let worst = [MistakeTally.Category.pitch, .missed, .extra, .timing].max { tally[$0] < tally[$1] }
            return worst.flatMap { tally[$0] > 0 ? $0 : nil }
        }
    }

    var range: Range
    /// Takes in the range, oldest first.
    var takes: [Take]
    var buckets: [Bucket]
    /// `.day` or `.weekOfYear`: what one bucket spans.
    var bucketUnit: Calendar.Component
    /// The chart's x span (the whole range, so empty days still show).
    var domain: ClosedRange<Date>
    var totals: MistakeTally
    var minutes: Int
    /// Of `minutes`, the time with the AI tutor.
    var tutorMinutes: Int
    var pagesCompleted: Int
    var trends: [Trend]
    var troubleSpots: [TroubleSpot]
    var pieces: [PieceSummary]

    var averageScore: Double? { takes.isEmpty ? nil : takes.map(\.score).reduce(0, +) / Double(takes.count) }
    var passes: Int { takes.filter(\.passed).count }

    /// The kind of mistake to work on next: the note-level one made most lately, or tempo when most recent takes drifted.
    var focus: Trend? {
        guard !trends.isEmpty else { return nil }
        if let tempo = trends.first(where: { $0.category == .tempo }), tempo.recent >= 50 { return tempo }
        let worst = trends.filter { $0.category != .tempo }.max { $0.recent < $1.recent }
        return worst.flatMap { $0.recent > 0 ? $0 : nil }
    }

    /// Minimum takes in the range before earlier and recent halves are compared.
    static let minTakesForTrend = 4

    static func build(takes allTakes: [Take], sessions: [PracticeSession], range: Range,
                      now: Date = Date(), calendar: Calendar = .current) -> StudentOverview {
        let today = calendar.startOfDay(for: now)
        let start: Date
        if let days = range.days {
            start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        } else {
            let first = [allTakes.map(\.date).min(), sessions.map(\.started).min()].compactMap { $0 }.min() ?? now
            start = calendar.startOfDay(for: first)
        }
        let takes = allTakes.filter { $0.date >= start && $0.date <= now }.sorted { $0.date < $1.date }
        let sessions = PracticeTotals.unique(sessions).filter { $0.started >= start && $0.started <= now }

        let spanDays = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        let unit: Calendar.Component = spanDays > 45 ? .weekOfYear : .day
        func bucketStart(_ date: Date) -> Date {
            unit == .day ? calendar.startOfDay(for: date)
                : (calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date))
        }

        var byStart: [Date: Bucket] = [:]
        for take in takes {
            let key = bucketStart(take.date)
            var b = byStart[key] ?? Bucket(start: key)
            if take.tutored { b.tutorTakes += 1 } else if take.isLesson { b.lessonTakes += 1 } else { b.otherTakes += 1 }
            b.tally = b.tally + take.tally
            b.scoreSum += take.score
            if let t = take.tempoDeviation { b.tempoSum += t; b.tempoCount += 1 }
            byStart[key] = b
        }
        let end = calendar.date(byAdding: unit, value: 1, to: bucketStart(now)) ?? now

        return StudentOverview(
            range: range,
            takes: takes,
            buckets: byStart.values.sorted { $0.start < $1.start },
            bucketUnit: unit,
            domain: bucketStart(start)...end,
            totals: takes.reduce(MistakeTally()) { $0 + $1.tally },
            minutes: sessions.reduce(0) { $0 + $1.minutes },
            tutorMinutes: sessions.filter { $0.kind == .tutor }.reduce(0) { $0 + $1.minutes },
            pagesCompleted: sessions.reduce(0) { $0 + $1.completedPages.count },
            trends: trends(takes),
            troubleSpots: troubleSpots(takes),
            pieces: pieces(takes))
    }

    /// Mistakes of a kind per 100 notes asked for; tempo is the share of takes (in %) that rushed, dragged or wandered.
    static func rate(_ category: MistakeTally.Category, _ tally: MistakeTally, takes: Int) -> Double {
        if category == .tempo { return takes > 0 ? 100 * Double(tally.tempo) / Double(takes) : 0 }
        return tally.expected > 0 ? 100 * Double(tally[category]) / Double(tally.expected) : 0
    }

    private static func trends(_ takes: [Take]) -> [Trend] {
        guard takes.count >= minTakesForTrend else { return [] }
        let half = takes.count / 2
        let earlier = Array(takes[..<half]), recent = Array(takes[half...])
        let e = earlier.reduce(MistakeTally()) { $0 + $1.tally }
        let r = recent.reduce(MistakeTally()) { $0 + $1.tally }
        return MistakeTally.Category.allCases.map {
            Trend(category: $0, earlier: rate($0, e, takes: earlier.count), recent: rate($0, r, takes: recent.count))
        }
    }

    /// Bars with mistakes in at least two takes, most first (at most five).
    private static func troubleSpots(_ takes: [Take]) -> [TroubleSpot] {
        struct Key: Hashable { var piece: PieceID; var measure: Int }
        var takesWithMistakes: [Key: Int] = [:]
        var kinds: [Key: [MistakeTally.Category: Int]] = [:]
        for take in takes {
            var seen = Set<Key>()
            for spot in take.spots {
                let key = Key(piece: pieceKey(take.piece), measure: spot.measure)
                kinds[key, default: [:]][spot.category, default: 0] += 1
                if seen.insert(key).inserted { takesWithMistakes[key, default: 0] += 1 }
            }
        }
        return takesWithMistakes
            .filter { $0.value >= 2 }
            .map { key, count in
                let category = kinds[key]?.max { ($0.value, $1.key.rawValue) < ($1.value, $0.key.rawValue) }?.key ?? .pitch
                return TroubleSpot(piece: key.piece, measure: key.measure, count: count, category: category)
            }
            .sorted { ($0.count, $1.piece.rawValue, $1.measure) > ($1.count, $0.piece.rawValue, $0.measure) }
            .prefix(5)
            .map { $0 }
    }

    /// Most played first.
    private static func pieces(_ takes: [Take]) -> [PieceSummary] {
        var all: [PieceID: PieceSummary] = [:]
        for take in takes {
            let key = pieceKey(take.piece)
            var p = all[key] ?? PieceSummary(piece: key, takes: 0, bestScore: 0, lastScore: 0,
                                             lastPlayed: take.date, tally: MistakeTally())
            p.takes += 1
            p.bestScore = max(p.bestScore, take.score)
            p.lastScore = take.score
            p.lastPlayed = take.date
            p.tally = p.tally + take.tally
            p.tutored = p.tutored || take.tutored
            all[key] = p
        }
        return all.values.sorted { ($0.takes, $0.lastPlayed) > ($1.takes, $1.lastPlayed) }
    }

    /// A lesson's blocks (`lesson:<unit>/<page>/<block>`) count as their page; anything else is itself.
    static func pieceKey(_ piece: PieceID) -> PieceID {
        guard piece.rawValue.hasPrefix("lesson:") else { return piece }
        let parts = piece.rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return piece }
        return PieceID(rawValue: parts[0...1].joined(separator: "/"))
    }
}

/// A piece the learner is learning with the AI tutor, and how far through its plan they are.
struct TutorLessonProgress: Identifiable, Equatable {
    var id: String
    var title: String
    var stepsDone: Int
    /// nil in progress saved before step counts were kept.
    var stepCount: Int?
    var stars: Int?
    var mastered: Bool
    var lastPlayed: Date

    /// Pieces under way with the tutor for `learner` (the tutor's learner key), most recent first.
    static func load(learner: String) -> [TutorLessonProgress] {
        PieceLessonStore.pages().compactMap { folder, page, _ in
            guard let p = PieceLessonStore.progress(folder, learner: learner), p.isUnderWay else { return nil }
            return TutorLessonProgress(id: folder, title: page.title, stepsDone: p.completedSteps.count,
                                       stepCount: p.stepCount, stars: p.lastStars, mastered: p.mastered, lastPlayed: p.saved)
        }
        .sorted { $0.lastPlayed > $1.lastPlayed }
    }
}

extension LearnerHistory {
    /// Every take whose report can be read, for the progress overview. Reads files: call off the main thread.
    func overviewTakes() -> [StudentOverview.Take] {
        let decoder = JSONDecoder()
        return allTakes().compactMap { take in
            guard let data = try? Data(contentsOf: take.reportURL),
                  let report = try? decoder.decode(GradeReport.self, from: data) else { return nil }
            let context = (try? Data(contentsOf: take.reportURL.deletingPathExtension().appendingPathExtension("tutor.json")))
                .flatMap { try? decoder.decode(TutorAttemptContext.self, from: $0) }
            return StudentOverview.Take(date: take.date, piece: take.piece, report: report, tutored: context != nil,
                                        printedMeasures: context?.printedMeasures)
        }
    }
}
#endif
