import Foundation
import PianoGraderCore

/// What's wrong with a unit folder. Every problem is reported, not just the first.
public enum UnitError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)
    case noPages
    case duplicatePage(String)
    case emptyPage(String)
    case unknownUnlock(page: String, target: String)
    case missingMIDI(page: String, block: Int, path: String)
    case badFingering(page: String, block: Int, finger: Int)
    case badTempo(page: String, block: Int)
    case badEarTraining(page: String, block: Int)
    case badSightReading(page: String, block: Int)

    public var description: String {
        switch self {
        case .unreadable(let why): return "Couldn't read unit.json: \(why)"
        case .noPages: return "The unit has no pages."
        case .duplicatePage(let id): return "Two pages have the ID \"\(id)\"."
        case .emptyPage(let id): return "Page \"\(id)\" has no blocks."
        case .unknownUnlock(let page, let target): return "Page \"\(page)\" unlocks \"\(target)\", which isn't in the unit."
        case .missingMIDI(let page, let block, let path): return "Page \"\(page)\" block \(block + 1): \(path) not found."
        case .badFingering(let page, let block, let finger): return "Page \"\(page)\" block \(block + 1): finger \(finger) (use 1–5)."
        case .badTempo(let page, let block): return "Page \"\(page)\" block \(block + 1): tempo must be above 0."
        case .badEarTraining(let page, let block): return "Page \"\(page)\" block \(block + 1): invalid ear-training stage, question count, threshold, or note pool."
        case .badSightReading(let page, let block): return "Page \"\(page)\" block \(block + 1): invalid sight-reading stage, question count, or threshold."
        }
    }
}

public struct UnitLoadFailure: Error, CustomStringConvertible {
    public let errors: [UnitError]
    public var description: String { errors.map(\.description).joined(separator: "\n") }
}

/// A unit read from its folder, with its MIDI paths resolved.
public struct LoadedUnit: Sendable {
    public let unit: LessonUnit
    public let folder: URL

    public static let fileName = "unit.json"

    /// Reads `<folder>/unit.json` and checks it. Throws `UnitLoadFailure` listing every problem.
    public static func load(folder: URL) throws -> LoadedUnit {
        let unit: LessonUnit
        do {
            let data = try Data(contentsOf: folder.appendingPathComponent(fileName))
            unit = try JSONDecoder().decode(LessonUnit.self, from: data)
        } catch {
            throw UnitLoadFailure(errors: [.unreadable(String(describing: error))])
        }
        let loaded = LoadedUnit(unit: unit, folder: folder)
        let errors = loaded.validate()
        if !errors.isEmpty { throw UnitLoadFailure(errors: errors) }
        return loaded
    }

    public init(unit: LessonUnit, folder: URL) {
        self.unit = unit
        self.folder = folder
    }

    public func url(for path: String) -> URL {
        folder.appendingPathComponent(path).standardizedFileURL
    }

    /// The MIDI file a block plays or grades against.
    public func midiURL(for block: Block) -> URL? {
        block.midi.map(url(for:))
    }

    /// Every problem with the unit; empty when it's fine to play.
    public func validate(fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> [UnitError] {
        var errors: [UnitError] = []
        if unit.pages.isEmpty { errors.append(.noPages) }
        var seen = Set<String>()
        for page in unit.pages where !seen.insert(page.id).inserted {
            errors.append(.duplicatePage(page.id))
        }
        for page in unit.pages {
            if page.blocks.isEmpty { errors.append(.emptyPage(page.id)) }
            if let target = page.unlocks, !seen.contains(target) {
                errors.append(.unknownUnlock(page: page.id, target: target))
            }
            for (i, block) in page.blocks.enumerated() {
                if case .earTraining(let b) = block {
                    let pool = b.notes
                    let validNotes = pool.map { b.level <= 2 && Set($0).count >= 2 && $0.allSatisfy { (0...11).contains($0) } } ?? true
                    let available = EarQuestionGenerator.examples(stage: b.stageID).map { Int($0.correctAnswer.id.replacingOccurrences(of: "note.", with: "")) }.compactMap { $0 }
                    if EarCurriculum.stage(b.stageID) == nil || !(1...20).contains(b.questions)
                        || !b.passAccuracy.isFinite || !(0...1).contains(b.passAccuracy) || !validNotes
                        || pool.map({ !Set($0).isSubset(of: Set(available)) }) == true {
                        errors.append(.badEarTraining(page: page.id, block: i))
                    }
                }
                if case .sightReading(let b) = block, SightCurriculum.stage(b.stageID) == nil || !(1...20).contains(b.questions)
                    || !b.passAccuracy.isFinite || !(0...1).contains(b.passAccuracy) {
                    errors.append(.badSightReading(page: page.id, block: i))
                }
                if let path = block.midi, !fileExists(url(for: path)) {
                    errors.append(.missingMIDI(page: page.id, block: i, path: path))
                }
                for finger in block.fingering ?? [] where !(1...5).contains(finger) {
                    errors.append(.badFingering(page: page.id, block: i, finger: finger))
                }
                if let tempo = Self.tempo(of: block), tempo <= 0 {
                    errors.append(.badTempo(page: page.id, block: i))
                }
            }
        }
        return errors
    }

    private static func tempo(of block: Block) -> Double? {
        switch block {
        case .listen(let b): return b.tempo
        case .timed(let b): return b.tempo
        default: return nil
        }
    }
}
