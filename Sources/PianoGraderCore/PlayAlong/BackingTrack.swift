import Foundation

/// A backing recording and how to play along with it, kept as metadata only: the audio file
/// is never changed. Trimming and "bar 1" are times in the original file.
///
/// Saved as JSON in the backing-track library (`BackingTrackLibrary`) and linked to passages
/// or MIDI files from there.
public struct BackingTrack: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// The original audio file (absolute path). If it moves, the library looks for a file of
    /// the same name next to the metadata.
    public var audioPath: String
    /// Length of the whole audio file in seconds.
    public var duration: Double
    /// Playback never starts before this (seconds into the file).
    public var trimStart: Double
    /// …and stops here (nil: the end of the file).
    public var trimEnd: Double?
    /// Where bar 1, beat 1 falls in the file (seconds). Bars before it are a pickup or intro.
    public var bar1Seconds: Double
    /// Tempo in quarter notes per minute.
    public var bpm: Double
    public var timeSignature: TimeSignature
    /// e.g. "C", "Bb", "F# minor".
    public var key: String?
    /// Clicks before playing starts.
    public var countInBars: Int
    public var notes: String?
    public var modified: Date

    public init(id: UUID = UUID(), name: String, audioPath: String, duration: Double, trimStart: Double = 0,
                trimEnd: Double? = nil, bar1Seconds: Double = 0, bpm: Double = 100,
                timeSignature: TimeSignature = .common, key: String? = nil, countInBars: Int = 1,
                notes: String? = nil, modified: Date = Date()) {
        self.id = id
        self.name = name
        self.audioPath = audioPath
        self.duration = max(0, duration)
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.bar1Seconds = bar1Seconds
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.key = key
        self.countInBars = countInBars
        self.notes = notes
        self.modified = modified
        clamp()
    }

    // MARK: Derived

    /// Where playback stops (seconds into the file).
    public var playEnd: Double { min(duration, trimEnd ?? duration) }

    /// Length of one bar in seconds of the recording.
    public var barSeconds: Double { timeSignature.quartersPerMeasure * 60 / max(1, bpm) }

    /// Length of one beat (the time signature's denominator note) in seconds.
    public var beatSeconds: Double { timeSignature.quartersPerBeat * 60 / max(1, bpm) }

    /// Bar `n` (1-based; 0 and below are bars before bar 1) starts at this time in the file.
    public func barStartSeconds(_ n: Int) -> Double { bar1Seconds + Double(n - 1) * barSeconds }

    /// Bar lines inside the trimmed region: (bar number, seconds). Bars before bar 1 are
    /// numbered 0, -1, …
    public func barLines() -> [(bar: Int, seconds: Double)] {
        guard barSeconds > 0 else { return [] }
        let first = Int(((trimStart - bar1Seconds) / barSeconds).rounded(.up)) + 1
        let last = Int(((playEnd - bar1Seconds) / barSeconds).rounded(.down)) + 1
        guard last >= first, last - first < 100_000 else { return [] }
        return (first...last).map { ($0, barStartSeconds($0)) }
    }

    /// Whole bars from bar 1 to the trim end.
    public var barCount: Int { max(0, Int(((playEnd - bar1Seconds) / barSeconds + 1e-6).rounded(.down))) }

    /// The annotation play-along uses: beat 0 of the reference is bar 1 of the recording.
    public func annotation(audioPath resolved: String? = nil) -> BackingAnnotation {
        var a = BackingAnnotation(file: resolved ?? audioPath, startSeconds: bar1Seconds, bpm: bpm,
                                  timeSignature: timeSignature, key: key, countInBars: countInBars)
        a.trimStartSeconds = trimStart
        a.trimEndSeconds = trimEnd
        return a
    }

    /// Keeps every time inside the file and in order (trim start ≤ bar 1 < trim end).
    public mutating func clamp() {
        bpm = min(400, max(20, bpm.isFinite ? bpm : 100))
        countInBars = min(4, max(0, countInBars))
        trimStart = min(max(0, trimStart), duration)
        if let end = trimEnd { trimEnd = end >= duration - 1e-4 ? nil : max(trimStart + 0.05, end) }
        bar1Seconds = min(max(trimStart, bar1Seconds), max(trimStart, playEnd - 0.01))
    }

    // MARK: Coding (time signature as "3/4")

    enum CodingKeys: String, CodingKey {
        case id, name, audioPath, duration, trimStart, trimEnd, bar1Seconds, bpm, timeSignature, key
        case countInBars, notes, modified
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        audioPath = try c.decode(String.self, forKey: .audioPath)
        duration = try c.decode(Double.self, forKey: .duration)
        trimStart = try c.decodeIfPresent(Double.self, forKey: .trimStart) ?? 0
        trimEnd = try c.decodeIfPresent(Double.self, forKey: .trimEnd)
        bar1Seconds = try c.decodeIfPresent(Double.self, forKey: .bar1Seconds) ?? 0
        bpm = try c.decode(Double.self, forKey: .bpm)
        let ts = try c.decodeIfPresent(String.self, forKey: .timeSignature) ?? "4/4"
        guard let parsed = TimeSignature(ts) else {
            throw DecodingError.dataCorruptedError(forKey: .timeSignature, in: c, debugDescription: "expected \"3/4\"")
        }
        timeSignature = parsed
        key = try c.decodeIfPresent(String.self, forKey: .key)
        countInBars = try c.decodeIfPresent(Int.self, forKey: .countInBars) ?? 1
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? Date(timeIntervalSince1970: 0)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(audioPath, forKey: .audioPath)
        try c.encode(duration, forKey: .duration)
        try c.encode(trimStart, forKey: .trimStart)
        try c.encodeIfPresent(trimEnd, forKey: .trimEnd)
        try c.encode(bar1Seconds, forKey: .bar1Seconds)
        try c.encode(bpm, forKey: .bpm)
        try c.encode("\(timeSignature.numerator)/\(timeSignature.denominator)", forKey: .timeSignature)
        try c.encodeIfPresent(key, forKey: .key)
        try c.encode(countInBars, forKey: .countInBars)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(modified, forKey: .modified)
    }

    /// Key names offered when annotating.
    public static let keyNames: [String] = {
        let majors = ["C", "G", "D", "A", "E", "B", "F#", "C#", "F", "Bb", "Eb", "Ab", "Db", "Gb", "Cb"]
        let minors = ["A", "E", "B", "F#", "C#", "G#", "D#", "A#", "D", "G", "C", "F", "Bb", "Eb", "Ab"]
        return majors + minors.map { $0 + " minor" }
    }()
}

/// What a backing track is linked to: a book passage, or a MIDI file opened on its own.
public enum BackingLinkKey {
    public static func passage(book: String, id: String) -> String { "passage:\(book)#\(id)" }
    public static func reference(path: String) -> String { "file:\(path)" }
}

/// Saved backing tracks (one JSON file each) and which passage uses which track.
///
/// ```
/// <directory>/tracks/<uuid>.backing.json
/// <directory>/links.json        { "passage:book.pdf#p29": "<uuid>", … }
/// ```
/// Not thread-safe: use from one thread (the main thread in the app).
public final class BackingTrackLibrary {
    public let directory: URL
    private var tracksDirectory: URL { directory.appendingPathComponent("tracks", isDirectory: true) }
    private var linksURL: URL { directory.appendingPathComponent("links.json") }
    private let fm = FileManager.default

    public init(directory: URL) {
        self.directory = directory
    }

    /// ~/Library/Application Support/PianoPad/Backing Tracks
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PianoPad/Backing Tracks", isDirectory: true)
    }

    private func fileURL(for id: UUID) -> URL {
        tracksDirectory.appendingPathComponent(id.uuidString + ".backing.json")
    }

    /// Every saved track, newest first. Files that can't be read are skipped.
    public func tracks() -> [BackingTrack] {
        guard let files = try? fm.contentsOfDirectory(at: tracksDirectory, includingPropertiesForKeys: nil) else { return [] }
        let decoder = Self.decoder()
        return files.filter { $0.lastPathComponent.hasSuffix(".backing.json") }
            .compactMap { try? decoder.decode(BackingTrack.self, from: Data(contentsOf: $0)) }
            .sorted { ($0.modified, $0.name) > ($1.modified, $1.name) }
    }

    public func track(_ id: UUID) -> BackingTrack? {
        guard let data = try? Data(contentsOf: fileURL(for: id)) else { return nil }
        return try? Self.decoder().decode(BackingTrack.self, from: data)
    }

    public func save(_ track: BackingTrack) throws {
        try fm.createDirectory(at: tracksDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(track).write(to: fileURL(for: track.id), options: .atomic)
    }

    /// Deletes the metadata (never the audio) and any links to it.
    public func delete(_ id: UUID) throws {
        if fm.fileExists(atPath: fileURL(for: id).path) { try fm.removeItem(at: fileURL(for: id)) }
        var all = links()
        all = all.filter { $0.value != id }
        try writeLinks(all)
    }

    // MARK: Links

    public func links() -> [String: UUID] {
        guard let data = try? Data(contentsOf: linksURL),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return raw.compactMapValues(UUID.init(uuidString:))
    }

    public func linkedTrackID(for key: String) -> UUID? { links()[key] }

    /// Links `key` to a track, or unlinks it with nil.
    public func link(_ key: String, to id: UUID?) throws {
        var all = links()
        all[key] = id
        try writeLinks(all)
    }

    private func writeLinks(_ links: [String: UUID]) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(links.mapValues(\.uuidString)).write(to: linksURL, options: .atomic)
    }

    /// Adds the backing tracks shipped inside the app to this library. `folder` has the same
    /// layout as a library (`tracks/<uuid>.backing.json`, `links.json`) plus each track's audio
    /// file at its top level, matched by the file name in the track's `audioPath`.
    ///
    /// Tracks already in the library (same id) are left alone, so a user's edits survive later
    /// launches, and existing links are never replaced. A `file:` link is moved onto the file of
    /// the same name in `referenceFolder` (the app's bundled examples), since the path it was
    /// saved with belongs to another Mac. Safe to call on every launch. Returns how many tracks
    /// were added.
    @discardableResult
    public func installBundled(from folder: URL, referenceFolder: URL? = nil) -> Int {
        let bundled = BackingTrackLibrary(directory: folder)
        var added = 0
        for var track in bundled.tracks() where self.track(track.id) == nil {
            let name = URL(fileURLWithPath: track.audioPath).lastPathComponent
            let source = folder.appendingPathComponent(name)
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = directory.appendingPathComponent(name)
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                if !fm.fileExists(atPath: destination.path) { try fm.copyItem(at: source, to: destination) }
                track.audioPath = destination.path
                try save(track)
                added += 1
            } catch {
                continue
            }
        }
        var current = links()
        var changed = false
        for (key, id) in bundled.links() where self.track(id) != nil {
            var newKey = key
            let prefix = "file:"
            if key.hasPrefix(prefix), let referenceFolder {
                let name = URL(fileURLWithPath: String(key.dropFirst(prefix.count))).lastPathComponent
                let candidate = referenceFolder.appendingPathComponent(name)
                guard fm.fileExists(atPath: candidate.path) else { continue }
                newKey = BackingLinkKey.reference(path: candidate.standardizedFileURL.path)
            }
            if current[newKey] == nil {
                current[newKey] = id
                changed = true
            }
        }
        if changed { try? writeLinks(current) }
        return added
    }

    /// Copies an audio file into the library folder and returns the copy, leaving the original
    /// untouched. The sandboxed app uses this on import, because it can't reopen a file outside
    /// its container on a later launch. A name already taken gets " 2", " 3"… appended.
    public func copyAudioIntoLibrary(_ source: URL) throws -> URL {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: destination.path) {
            let name = "\(stem) \(n)" + (ext.isEmpty ? "" : ".\(ext)")
            destination = directory.appendingPathComponent(name)
            n += 1
        }
        try fm.copyItem(at: source, to: destination)
        return destination
    }

    /// The audio file for a track: its saved path, else a file with the same name in the
    /// library folder or next to `alsoLookIn`. nil if missing.
    public func resolveAudio(for track: BackingTrack, alsoLookIn other: URL? = nil) -> URL? {
        let original = URL(fileURLWithPath: track.audioPath)
        if fm.fileExists(atPath: original.path) { return original }
        let name = original.lastPathComponent
        for folder in [directory, other].compactMap({ $0 }) {
            let candidate = folder.appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
