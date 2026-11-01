import Foundation

/// How a learner is doing on one piece. What the what-to-practise-next coach and the
/// persona-per-piece setting will read.
public struct PieceProgress: Codable, Equatable, Sendable {
    /// Graded takes.
    public var attempts: Int
    /// Best grade score (0–1) so far.
    public var bestScore: Double
    /// The most recent take's score.
    public var lastScore: Double
    public var lastPlayed: Date
    /// When the piece was first passed; nil until then.
    public var completedAt: Date?

    public var isCompleted: Bool { completedAt != nil }

    public init(attempts: Int = 0, bestScore: Double = 0, lastScore: Double = 0,
                lastPlayed: Date = Date(), completedAt: Date? = nil) {
        self.attempts = attempts
        self.bestScore = bestScore
        self.lastScore = lastScore
        self.lastPlayed = lastPlayed
        self.completedAt = completedAt
    }
}

/// One saved take.
public struct SavedTake: Equatable, Sendable {
    public var piece: PieceID
    /// `<timestamp>.mid`
    public var midiURL: URL
    /// `<timestamp>.json`: the grade report, as the app encoded it.
    public var reportURL: URL
    public var date: Date
}

/// A learner's takes and progress, inside their folder:
///
/// ```
/// <learner folder>/takes/<PieceID.folderName>/<yyyyMMdd-HHmmss-SSS>.mid   the take
/// <learner folder>/takes/<PieceID.folderName>/<yyyyMMdd-HHmmss-SSS>.json  its grade report
/// <learner folder>/progress.json                                          { PieceID: PieceProgress }
/// <learner folder>/lessons.json                                           { lesson page: PageProgress }
/// <learner folder>/sessions.json                                          [PracticeSession], oldest first
/// ```
///
/// The report is opaque `Data` (the app's encoded `GradeReport`), so this target doesn't
/// depend on PianoGraderCore. Not thread-safe: use from one thread.
public final class LearnerHistory {
    public let folder: URL
    private let fm = FileManager.default
    private var takesDirectory: URL { folder.appendingPathComponent("takes", isDirectory: true) }
    private var progressURL: URL { folder.appendingPathComponent("progress.json") }

    public init(folder: URL) {
        self.folder = folder
    }

    // MARK: Recording

    /// Saves a graded take and updates the piece's progress. Returns the saved take.
    @discardableResult
    public func record(piece: PieceID, midi: Data, report: Data, score: Double, passed: Bool,
                       at date: Date = Date(), contributesToProgress: Bool = true) throws -> SavedTake {
        let dir = takesDirectory.appendingPathComponent(piece.folderName, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var stem = Self.stamp(date)
        var n = 2
        while fm.fileExists(atPath: dir.appendingPathComponent(stem + ".mid").path) {
            stem = Self.stamp(date) + "-\(n)"
            n += 1
        }
        let midiURL = dir.appendingPathComponent(stem + ".mid")
        let reportURL = dir.appendingPathComponent(stem + ".json")
        try midi.write(to: midiURL, options: .atomic)
        try report.write(to: reportURL, options: .atomic)

        if !contributesToProgress { return SavedTake(piece: piece, midiURL: midiURL, reportURL: reportURL, date: date) }
        var all = progress()
        var p = all[piece] ?? PieceProgress(lastPlayed: date)
        let score = min(1, max(0, score))
        p.attempts += 1
        p.bestScore = max(p.bestScore, score)
        p.lastScore = score
        p.lastPlayed = date
        if passed && p.completedAt == nil { p.completedAt = date }
        all[piece] = p
        try writeProgress(all)
        return SavedTake(piece: piece, midiURL: midiURL, reportURL: reportURL, date: date)
    }

    // MARK: Reading

    /// Progress per piece. Missing or unreadable → empty.
    public func progress() -> [PieceID: PieceProgress] {
        guard let data = try? Data(contentsOf: progressURL),
              let raw = try? Self.decoder().decode([String: PieceProgress].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.map { (PieceID(rawValue: $0.key), $0.value) })
    }

    public func progress(for piece: PieceID) -> PieceProgress? { progress()[piece] }

    /// The piece's saved takes, oldest first.
    public func takes(for piece: PieceID) -> [SavedTake] {
        let dir = takesDirectory.appendingPathComponent(piece.folderName, isDirectory: true)
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "mid" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                let stem = url.deletingPathExtension().lastPathComponent
                let date = Self.date(fromStem: stem) ?? Date.distantPast
                return SavedTake(piece: piece, midiURL: url,
                                 reportURL: url.deletingPathExtension().appendingPathExtension("json"), date: date)
            }
    }

    // MARK: Reset

    /// Removes every take and all progress, lessons and sessions included; settings are kept.
    public func reset() throws {
        if fm.fileExists(atPath: takesDirectory.path) { try fm.removeItem(at: takesDirectory) }
        if fm.fileExists(atPath: progressURL.path) { try fm.removeItem(at: progressURL) }
        if fm.fileExists(atPath: lessonsURL.path) { try fm.removeItem(at: lessonsURL) }
        if fm.fileExists(atPath: sessionsURL.path) { try fm.removeItem(at: sessionsURL) }
        if fm.fileExists(atPath: earTrainingURL.path) { try fm.removeItem(at: earTrainingURL) }
    }

    // MARK: Private

    private func writeProgress(_ all: [PieceID: PieceProgress]) throws {
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let raw = Dictionary(uniqueKeysWithValues: all.map { ($0.key.rawValue, $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(raw).write(to: progressURL, options: .atomic)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f
    }()

    static func stamp(_ date: Date) -> String { stampFormatter.string(from: date) }

    static func date(fromStem stem: String) -> Date? {
        stampFormatter.date(from: String(stem.prefix(19)))
    }
}

extension LearnerStore {
    /// The learner's takes and progress.
    public func history(for id: UUID) -> LearnerHistory {
        LearnerHistory(folder: folder(for: id))
    }
}
