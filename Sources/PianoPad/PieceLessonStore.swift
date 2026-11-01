#if os(macOS)
import CryptoKit
import Foundation
import PianoGraderCore
import PianoLessons

/// Lesson plans and the Learn pages made from them, one folder per piece:
/// `PianoPad/PieceLessons/<key>/` holds `plan.json`, `lesson.json` (a LessonPage) and the
/// MIDI files the page plays. The key is the saved piece's folder name for pieces imported
/// from Books, else a hash of the MIDI file.
enum PieceLessonStore {
    /// Tests point this at a temporary folder.
    static var rootOverride: URL?
    static var root: URL { rootOverride ?? BookLibrary.support.appendingPathComponent("PieceLessons") }

    static func folder(_ key: String) -> URL { root.appendingPathComponent(key) }

    /// The key for a piece's MIDI file.
    static func key(for url: URL) -> String {
        let imported = BookLibrary.importedFolder.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        if path.hasPrefix(imported) {
            return url.deletingLastPathComponent().lastPathComponent
        }
        let data = (try? Data(contentsOf: url)) ?? Data(path.utf8)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "midi-" + hash.prefix(16)
    }

    // MARK: Plans

    /// The cached plan, unless it was made by an older planner.
    static func plan(_ key: String) -> LessonPlan? {
        guard let data = try? Data(contentsOf: folder(key).appendingPathComponent("plan.json")),
              let plan = try? JSONDecoder().decode(LessonPlan.self, from: data),
              plan.version == LessonPlan.currentVersion else { return nil }
        return plan
    }

    static func save(_ plan: LessonPlan, key: String) throws {
        let dir = folder(key)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(plan).write(to: dir.appendingPathComponent("plan.json"), options: .atomic)
    }

    // MARK: Tutor progress

    /// Where `learner` got to in this piece's planned lesson ("default" without a learner).
    static func progress(_ key: String, learner: String) -> PiecePracticeEngine.Progress? {
        guard let data = try? Data(contentsOf: progressURL(key, learner: learner)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PiecePracticeEngine.Progress.self, from: data)
    }

    static func save(_ progress: PiecePracticeEngine.Progress, key: String, learner: String) {
        let url = progressURL(key, learner: learner)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(progress).write(to: url, options: .atomic)
    }

    static func clearProgress(_ key: String, learner: String) {
        try? FileManager.default.removeItem(at: progressURL(key, learner: learner))
    }

    private static func progressURL(_ key: String, learner: String) -> URL {
        folder(key).appendingPathComponent("progress-\(learner).json")
    }

    // MARK: Learn pages

    /// Writes the plan's lesson page and its MIDI files.
    static func writeLesson(_ plan: LessonPlan, sequence: MIDISequence, title: String, key: String, slowPercent: Double) throws {
        let out = PieceLessonBuilder.build(plan: plan, sequence: sequence, title: title, id: "piece-\(key)", slowPercent: slowPercent)
        let dir = folder(key)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, music) in out.files {
            let data = MIDIFile.write(notes: music.notes, tempoBPM: music.initialTempoBPM,
                                      timeSignature: music.timeSignature, keySignature: music.keySignature)
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(out.page).write(to: dir.appendingPathComponent("lesson.json"), options: .atomic)
    }

    /// Every piece with a lesson page, newest first.
    static func pages() -> [(folder: String, page: LessonPage, modified: Date)] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return dirs.compactMap { dir -> (String, LessonPage, Date)? in
            let file = dir.appendingPathComponent("lesson.json")
            guard let data = try? Data(contentsOf: file),
                  let page = try? JSONDecoder().decode(LessonPage.self, from: data) else { return nil }
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return (dir.lastPathComponent, page, date)
        }
        .sorted { $0.2 > $1.2 }
        .map { (folder: $0.0, page: $0.1, modified: $0.2) }
    }

    /// The learner's pieces as one unit for Learn (nil when there are none).
    static func unit() -> LoadedUnit? {
        let all = pages()
        guard !all.isEmpty else { return nil }
        return LoadedUnit(unit: PieceLessonBuilder.unit(pages: all.map { (folder: $0.folder, page: $0.page) }), folder: root)
    }
}
#endif
