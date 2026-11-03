import Foundation

public struct CatalogPiece: Codable, Identifiable, Equatable, Sendable {
    public enum Difficulty: String, Codable, CaseIterable, Sendable {
        case elementary = "Elementary", intermediate = "Intermediate", advanced = "Advanced"
    }
    public let id: String
    public let title: String
    public let composer: String
    public let difficulty: Difficulty
    public let attribution: String
    public let license: String
    public let licenseURL: URL
    public let sourceURL: URL
    public let pdfURL: URL
    public let lilypondURL: URL
    public let midiURL: URL
    public let sha256: String
    public let review: String

    public func matches(query: String, composer: String? = nil, difficulty: Difficulty? = nil) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        let text = title + " " + self.composer
        return (composer == nil || composer == self.composer)
            && (difficulty == nil || difficulty == self.difficulty)
            && words.allSatisfy { text.localizedStandardContains(String($0)) }
    }
}

public struct MusicCatalog: Codable, Sendable {
    public let sourceRevision: String
    public let pieces: [CatalogPiece]

    public static func bundled() throws -> MusicCatalog {
        guard let url = Bundle.module.url(forResource: "mutopia", withExtension: "json") else {
            throw CatalogError.invalidCatalog
        }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> MusicCatalog {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard !catalog.pieces.isEmpty,
              Set(catalog.pieces.map(\.id)).count == catalog.pieces.count,
              catalog.pieces.allSatisfy({ piece in
                  !piece.id.isEmpty && !piece.title.isEmpty && !piece.composer.isEmpty
                    && !piece.attribution.isEmpty && !piece.review.isEmpty
                    && ["Public Domain", "CC BY 2.5", "CC BY 3.0", "CC BY 4.0"].contains(piece.license)
                    && piece.sha256.count == 64
                    && piece.sha256.allSatisfy { "0123456789abcdef".contains($0) }
                    && [piece.licenseURL, piece.sourceURL, piece.pdfURL, piece.lilypondURL, piece.midiURL]
                        .allSatisfy { $0.scheme == "https" && $0.host != nil }
              }) else { throw CatalogError.invalidCatalog }
        return catalog
    }
}

public enum CatalogError: LocalizedError {
    case invalidCatalog, http(Int), tooLarge, checksum, invalidMIDI
    public var errorDescription: String? {
        switch self {
        case .invalidCatalog: return "The music catalog could not be read. Please update the app."
        case .http(let status): return "Mutopia returned HTTP \(status). Please try again."
        case .tooLarge: return "This download is larger than expected. Please try another piece."
        case .checksum: return "This file differs from the reviewed edition. Please update the app or try another piece."
        case .invalidMIDI: return "This file contains no playable piano music. Please try another piece."
        }
    }
}
