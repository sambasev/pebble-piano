import Foundation

/// A stable name for a piece, used to key takes, progress and per-piece settings.
///
/// - `passage:<id>` for a passage in a book (the same key backing-track links use).
/// - `file:<hash>` for a loose MIDI file, hashed by content, so renaming or moving the file
///   keeps its history.
public struct PieceID: RawRepresentable, Codable, Hashable, Comparable, CustomStringConvertible, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func passage(_ id: String) -> PieceID {
        PieceID(rawValue: "passage:" + id)
    }

    public static func file(contents: Data) -> PieceID {
        PieceID(rawValue: "file:" + fnv1a64Hex(contents))
    }

    public static func file(at url: URL) throws -> PieceID {
        file(contents: try Data(contentsOf: url))
    }

    public var isPassage: Bool { rawValue.hasPrefix("passage:") }
    public var isFile: Bool { rawValue.hasPrefix("file:") }

    /// The passage ID for a `passage:` piece, else nil.
    public var passageID: String? {
        isPassage ? String(rawValue.dropFirst("passage:".count)) : nil
    }

    /// A single path component safe to use as a folder name (`takes/<folderName>/`).
    public var folderName: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.")
        return rawValue.addingPercentEncoding(withAllowedCharacters: allowed) ?? rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: PieceID, rhs: PieceID) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 64-bit FNV-1a as 16 hex digits: an identity for a file's contents, not a security hash.
    static func fnv1a64Hex(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
