import Foundation

public enum LearnerStoreError: Error, Equatable {
    case emptyName
    case unknownLearner(UUID)
}

/// The learners on this Mac and each one's settings, on disk:
///
/// ```
/// <baseURL>/learners.json                  { "version": 1, "learners": [ … ] }
/// <baseURL>/Learners/<uuid>/settings.json  LearnerSettings
/// ```
///
/// The active learner's ID is kept in `UserDefaults` (`PianoPad.activeLearner`); if it is
/// missing or names a deleted learner, the first learner is active.
///
/// Files that are missing load as empty. A `learners.json` that can't be read is moved aside
/// (`learners.json.unreadable-<time>`) rather than overwritten, so nothing is lost by the next
/// save. Not thread-safe: use from one thread (the main thread in the app).
public final class LearnerStore {
    public let baseURL: URL
    public private(set) var learners: [Learner] = []

    public static let activeLearnerKey = "PianoPad.activeLearner"

    private let defaults: UserDefaults
    private let fm = FileManager.default
    private var learnersURL: URL { baseURL.appendingPathComponent("learners.json") }
    private var learnersDirectory: URL { baseURL.appendingPathComponent("Learners", isDirectory: true) }

    /// ~/Library/Application Support/PianoPad (inside the app's container when sandboxed).
    public static var defaultBaseURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PianoPad", isDirectory: true)
    }

    public init(baseURL: URL = LearnerStore.defaultBaseURL, defaults: UserDefaults = .standard) {
        self.baseURL = baseURL
        self.defaults = defaults
        load()
    }

    // MARK: Learners

    public func learner(_ id: UUID) -> Learner? {
        learners.first { $0.id == id }
    }

    /// The active learner: the one saved in `UserDefaults`, else the first; nil when there are none.
    public var activeLearner: Learner? {
        if let raw = defaults.string(forKey: Self.activeLearnerKey), let id = UUID(uuidString: raw),
           let learner = learner(id) {
            return learner
        }
        return learners.first
    }

    public func setActive(_ id: UUID) throws {
        guard learner(id) != nil else { throw LearnerStoreError.unknownLearner(id) }
        defaults.set(id.uuidString, forKey: Self.activeLearnerKey)
    }

    /// Adds a learner and saves. The name is trimmed and must not be empty.
    @discardableResult
    public func add(name: String, avatar: String = Learner.defaultAvatar, kind: Learner.Kind,
                    level: Learner.Level? = nil) throws -> Learner {
        // Whole seconds, so the learner in memory equals the one read back from ISO 8601.
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let learner = Learner(name: try Self.validName(name), avatar: avatar, kind: kind, level: level,
                              createdAt: now)
        learners.append(learner)
        do {
            try saveLearners()
        } catch {
            learners.removeLast()
            throw error
        }
        return learner
    }

    public func rename(_ id: UUID, to name: String) throws {
        let name = try Self.validName(name)
        try update(id) { $0.name = name }
    }

    public func setAvatar(_ id: UUID, to avatar: String) throws {
        try update(id) { $0.avatar = avatar }
    }

    public func setKind(_ id: UUID, to kind: Learner.Kind) throws {
        try update(id) { $0.kind = kind }
    }

    /// Removes the learner and everything in their folder (settings, and later takes and
    /// progress). If they were active, the first remaining learner becomes active.
    public func delete(_ id: UUID) throws {
        guard let index = learners.firstIndex(where: { $0.id == id }) else {
            throw LearnerStoreError.unknownLearner(id)
        }
        let removed = learners.remove(at: index)
        do {
            try saveLearners()
        } catch {
            learners.insert(removed, at: index)
            throw error
        }
        if defaults.string(forKey: Self.activeLearnerKey) == id.uuidString {
            defaults.removeObject(forKey: Self.activeLearnerKey)
        }
        let dir = folder(for: id)
        if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
    }

    // MARK: Per-learner files

    /// `<baseURL>/Learners/<uuid>/`. Not created until something is saved there.
    public func folder(for id: UUID) -> URL {
        learnersDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// The learner's settings, or defaults if none are saved (or the file can't be read).
    public func settings(for id: UUID) -> LearnerSettings {
        guard let data = try? Data(contentsOf: settingsURL(for: id)),
              let settings = try? Self.decoder().decode(LearnerSettings.self, from: data) else {
            return LearnerSettings()
        }
        return settings
    }

    public func save(_ settings: LearnerSettings, for id: UUID) throws {
        guard learner(id) != nil else { throw LearnerStoreError.unknownLearner(id) }
        try fm.createDirectory(at: folder(for: id), withIntermediateDirectories: true)
        try Self.encoder().encode(settings).write(to: settingsURL(for: id), options: .atomic)
    }

    // MARK: Private

    private struct LearnersFile: Codable {
        var version: Int
        var learners: [Learner]
    }

    private static let fileVersion = 1

    private func settingsURL(for id: UUID) -> URL {
        folder(for: id).appendingPathComponent("settings.json")
    }

    private func update(_ id: UUID, _ change: (inout Learner) -> Void) throws {
        guard let index = learners.firstIndex(where: { $0.id == id }) else {
            throw LearnerStoreError.unknownLearner(id)
        }
        let old = learners[index]
        change(&learners[index])
        do {
            try saveLearners()
        } catch {
            learners[index] = old
            throw error
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: learnersURL) else {
            learners = []
            return
        }
        if let file = try? Self.decoder().decode(LearnersFile.self, from: data) {
            learners = file.learners
        } else {
            learners = []
            moveAsideUnreadableFile()
        }
    }

    private func moveAsideUnreadableFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = baseURL.appendingPathComponent("learners.json.unreadable-\(stamp)")
        try? fm.moveItem(at: learnersURL, to: aside)
    }

    private func saveLearners() throws {
        try fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let file = LearnersFile(version: Self.fileVersion, learners: learners)
        try Self.encoder().encode(file).write(to: learnersURL, options: .atomic)
    }

    private static func validName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LearnerStoreError.emptyName }
        return trimmed
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
