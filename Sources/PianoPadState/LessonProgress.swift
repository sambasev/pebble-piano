import Foundation

extension PieceID {
    /// A lesson page: `lesson:<unit>/<page>`. Keys the page's entry in `lessons.json`.
    public static func lessonPage(unit: String, page: String) -> PieceID {
        PieceID(rawValue: "lesson:\(unit)/\(page)")
    }

    /// One graded block on a lesson page: `lesson:<unit>/<page>/<block>` (block index from 0).
    /// Its takes go into the usual `takes/` folder.
    public static func lesson(unit: String, page: String, block: Int) -> PieceID {
        PieceID(rawValue: "lesson:\(unit)/\(page)/\(block)")
    }

    public var isLesson: Bool { rawValue.hasPrefix("lesson:") }
}

/// Where a learner is on one lesson page.
public struct PageProgress: Codable, Equatable, Sendable {
    /// The block to resume at (index from 0).
    public var currentBlock: Int
    /// Best page stars so far (0–3); nil for pages without starred blocks or not yet finished.
    public var bestStars: Int?
    /// Stars from the most recent finish.
    public var lastStars: Int?
    /// Times the page was finished.
    public var completions: Int
    /// First finished; nil until then.
    public var completedAt: Date?
    public var lastPlayed: Date
    /// Blocks skipped or moved on from without passing, on the most recent finish.
    public var flaggedBlocks: [Int]

    public var isCompleted: Bool { completedAt != nil }

    public init(currentBlock: Int = 0, bestStars: Int? = nil, lastStars: Int? = nil, completions: Int = 0,
                completedAt: Date? = nil, lastPlayed: Date = Date(), flaggedBlocks: [Int] = []) {
        self.currentBlock = currentBlock
        self.bestStars = bestStars
        self.lastStars = lastStars
        self.completions = completions
        self.completedAt = completedAt
        self.lastPlayed = lastPlayed
        self.flaggedBlocks = flaggedBlocks
    }

    private enum CodingKeys: String, CodingKey {
        case currentBlock, bestStars, lastStars, completions, completedAt, lastPlayed, flaggedBlocks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentBlock = try c.decodeIfPresent(Int.self, forKey: .currentBlock) ?? 0
        bestStars = try c.decodeIfPresent(Int.self, forKey: .bestStars)
        lastStars = try c.decodeIfPresent(Int.self, forKey: .lastStars)
        completions = try c.decodeIfPresent(Int.self, forKey: .completions) ?? 0
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed) ?? Date.distantPast
        flaggedBlocks = try c.decodeIfPresent([Int].self, forKey: .flaggedBlocks) ?? []
    }
}

/// Lesson progress, in `<learner folder>/lessons.json` as `{ "lesson:u1/p2": PageProgress }`.
extension LearnerHistory {
    var lessonsURL: URL { folder.appendingPathComponent("lessons.json") }

    /// Progress per lesson page. Missing or unreadable → empty.
    public func lessonProgress() -> [PieceID: PageProgress] {
        guard let data = try? Data(contentsOf: lessonsURL),
              let raw = try? Self.jsonDecoder().decode([String: PageProgress].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.map { (PieceID(rawValue: $0.key), $0.value) })
    }

    public func lessonProgress(unit: String, page: String) -> PageProgress? {
        lessonProgress()[.lessonPage(unit: unit, page: page)]
    }

    /// Remembers the block to resume at.
    public func saveLessonPosition(unit: String, page: String, block: Int, at date: Date = Date()) throws {
        try updateLessons(unit: unit, page: page, at: date) { p in
            p.currentBlock = max(0, block)
        }
    }

    /// Records a finished page: stars, flags, completion. The resume point goes back to block 0.
    public func recordPageComplete(unit: String, page: String, stars: Int?, flaggedBlocks: [Int],
                                   at date: Date = Date()) throws {
        try updateLessons(unit: unit, page: page, at: date) { p in
            p.currentBlock = 0
            p.completions += 1
            p.lastStars = stars
            if let stars { p.bestStars = max(p.bestStars ?? 0, stars) }
            p.flaggedBlocks = flaggedBlocks
            if p.completedAt == nil { p.completedAt = date }
        }
    }

    /// IDs of completed pages in a unit, for `Unit.isUnlocked` and `Unit.nextPage`.
    public func completedPages(unit: String) -> Set<String> {
        let prefix = "lesson:\(unit)/"
        return Set(lessonProgress().compactMap { key, value in
            value.isCompleted && key.rawValue.hasPrefix(prefix) ? String(key.rawValue.dropFirst(prefix.count)) : nil
        })
    }

    private func updateLessons(unit: String, page: String, at date: Date, _ change: (inout PageProgress) -> Void) throws {
        var all = lessonProgress()
        let key = PieceID.lessonPage(unit: unit, page: page)
        var p = all[key] ?? PageProgress(lastPlayed: date)
        change(&p)
        p.lastPlayed = date
        all[key] = p
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let raw = Dictionary(uniqueKeysWithValues: all.map { ($0.key.rawValue, $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(raw).write(to: lessonsURL, options: .atomic)
    }

    static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
