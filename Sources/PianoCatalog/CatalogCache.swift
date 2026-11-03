import Foundation
import CryptoKit
import PianoGraderCore

public protocol CatalogTransport: Sendable {
    func download(_ url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> Data
}

public struct MutopiaTransport: CatalogTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func download(_ url: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw CatalogError.invalidMIDI }
        guard (200..<300).contains(http.statusCode) else { throw CatalogError.http(http.statusCode) }
        let maximum = 5 * 1024 * 1024
        guard response.expectedContentLength <= maximum else { throw CatalogError.tooLarge }
        let expected = response.expectedContentLength
        progress(nil)
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximum else { throw CatalogError.tooLarge }
            data.append(byte)
            if data.count % 1024 == 0 {
                progress(expected > 0 ? min(0.99, Double(data.count) / Double(expected)) : nil)
            }
        }
        try Task.checkCancellation()
        return data
    }
}

/// Owns only reviewed MIDI files. Persistent storage makes downloaded pieces available offline.
public actor CatalogCache {
    public let directory: URL
    private let transport: any CatalogTransport

    public init(directory: URL = CatalogCache.defaultDirectory, transport: any CatalogTransport = MutopiaTransport()) {
        self.directory = directory
        self.transport = transport
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("PerfectPiano/MusicLibrary", isDirectory: true)
    }

    private func url(for piece: CatalogPiece) -> URL {
        // The hash itself is encoded, rather than trusting catalog IDs as filesystem paths.
        let name = Self.digest(Data(piece.sha256.utf8))
        return directory.appendingPathComponent(name).appendingPathExtension("mid")
    }

    public func downloadedIDs(in pieces: [CatalogPiece]) -> Set<String> {
        Set(pieces.filter { cachedURL(for: $0) != nil }.map(\.id))
    }

    public func cachedURL(for piece: CatalogPiece) -> URL? {
        let destination = url(for: piece)
        guard let data = try? Data(contentsOf: destination), (try? Self.validate(data, for: piece)) != nil else { return nil }
        return destination
    }

    public func prepare(_ piece: CatalogPiece, progress: @escaping @Sendable (Double?) -> Void = { _ in }) async throws -> URL {
        try Task.checkCancellation()
        if let cached = cachedURL(for: piece) { progress(1); return cached }
        let data = try await transport.download(piece.midiURL, progress: progress)
        try Task.checkCancellation()
        try Self.validate(data, for: piece)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Task.checkCancellation()
        let destination = url(for: piece)
        try data.write(to: destination, options: .atomic)
        progress(1)
        return destination
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func validate(_ data: Data, for piece: CatalogPiece) throws {
        guard data.count <= 5 * 1024 * 1024 else { throw CatalogError.tooLarge }
        guard digest(data) == piece.sha256 else { throw CatalogError.checksum }
        let sequence: MIDISequence
        do { sequence = try MIDIFile.parse(data) } catch { throw CatalogError.invalidMIDI }
        guard !sequence.notes.isEmpty, sequence.notes.allSatisfy({ $0.channel != 9 && (21...108).contains($0.pitch) }) else {
            throw CatalogError.invalidMIDI
        }
    }
}
