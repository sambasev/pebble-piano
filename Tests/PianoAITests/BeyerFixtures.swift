import Foundation
@testable import PianoAI

/// The Beyer Op. 101 test pieces in Fixtures/beyer: system images (1895 scan crops and the
/// modern re-engraving), Muse Wonder's saved readings of them, and the verified answer key.
enum BeyerFixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/beyer")

    enum Source: String, CaseIterable { case scan, modern
        var imageFolder: String { self == .scan ? "crops" : "modern" }
    }

    /// piece → the crops it spans, in order.
    static let pieces: [(String, [String])] = [("no12", ["no12"]), ("no13", ["no13"]), ("no24", ["no24a", "no24b"])]

    static func image(_ crop: String, _ source: Source) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("\(source.imageFolder)/\(crop).png"))
    }

    static func reading(_ crop: String, _ source: Source) throws -> SystemReading {
        let url = root.appendingPathComponent("readings/\(source.rawValue)/muse-wonder-1.0-\(crop).json")
        return try JSONDecoder().decode(SystemReading.self, from: Data(contentsOf: url))
    }

    struct TruthPiece: Decodable {
        var crops: [String]
        var measures: [[String: [[String]]]]
    }

    /// piece → bars → staff ("upper"/"lower") → [[name, duration]].
    static func truth() throws -> [String: TruthPiece] {
        try JSONDecoder().decode([String: TruthPiece].self,
                                 from: Data(contentsOf: root.appendingPathComponent("truth/pieces.json")))
    }
}
