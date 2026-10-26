import Foundation
import PianoGraderCore

/// Saved takes with your own pass/fail verdict. `grade check` re-grades them all,
/// which is both the milestone's exit gate and a regression suite for threshold changes.
///
/// Layout: fixtures/<reference>-<time>/{reference.mid, take.mid, rubric.md|rubric.yaml, fixture.json}
struct FixtureStore {
    struct Meta: Codable {
        var label: Verdict
        var createdAt: Date
        var referenceName: String
        var takeName: String
    }

    struct Fixture {
        let directory: URL
        let meta: Meta
        var referenceURL: URL { directory.appendingPathComponent("reference.mid") }
        var takeURL: URL { directory.appendingPathComponent("take.mid") }

        func rubric() throws -> Rubric {
            for name in ["rubric.md", "rubric.yaml", "rubric.yml"] {
                let url = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { return try Rubric.load(url: url) }
            }
            return .beginner
        }
    }

    let directory: URL

    func save(reference: URL, take: URL, rubric: URL?, label: Verdict) throws -> URL {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = reference.deletingPathExtension().lastPathComponent
        var dir = directory.appendingPathComponent("\(stem)-\(formatter.string(from: Date()))")
        var suffix = 2
        while fm.fileExists(atPath: dir.path) {
            dir = directory.appendingPathComponent("\(stem)-\(formatter.string(from: Date()))-\(suffix)")
            suffix += 1
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.copyItem(at: reference, to: dir.appendingPathComponent("reference.mid"))
        try fm.copyItem(at: take, to: dir.appendingPathComponent("take.mid"))
        if let rubric {
            let ext = rubric.pathExtension.isEmpty ? "yaml" : rubric.pathExtension
            try fm.copyItem(at: rubric, to: dir.appendingPathComponent("rubric.\(ext)"))
        }
        let meta = Meta(label: label, createdAt: Date(), referenceName: reference.lastPathComponent, takeName: take.lastPathComponent)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(meta).write(to: dir.appendingPathComponent("fixture.json"))
        return dir
    }

    func all() throws -> [Fixture] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dirs = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return dirs.compactMap { dir in
            let metaURL = dir.appendingPathComponent("fixture.json")
            guard let data = try? Data(contentsOf: metaURL),
                  let meta = try? decoder.decode(Meta.self, from: data) else { return nil }
            return Fixture(directory: dir, meta: meta)
        }
    }
}
