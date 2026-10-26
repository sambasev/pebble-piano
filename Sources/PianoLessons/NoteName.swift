import Foundation

/// A note written as a name in lesson files ("C4", "F#3", "Bb4"), held as a MIDI pitch.
/// Middle C is C4 (60). Encodes back to the name with sharps.
public struct NoteName: Codable, Hashable, Sendable, CustomStringConvertible {
    public let pitch: Int

    public init(pitch: Int) {
        self.pitch = pitch
    }

    private static let letters: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
    private static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Parses a letter (A–G, either case), any number of accidentals (#, b, ♯, ♭) and an
    /// octave number (may be negative). Returns nil for anything else or a pitch outside 0–127.
    public init?(_ text: String) {
        var chars = Substring(text.trimmingCharacters(in: .whitespaces))
        guard let first = chars.first else { return nil }
        let upper = String(first).uppercased()
        guard upper.count == 1, let base = Self.letters[Character(upper)] else { return nil }
        chars = chars.dropFirst()
        var shift = 0
        while let c = chars.first, "#b♯♭".contains(c) {
            shift += (c == "#" || c == "♯") ? 1 : -1
            chars = chars.dropFirst()
        }
        guard !chars.isEmpty, let octave = Int(chars) else { return nil }
        let pitch = (octave + 1) * 12 + base + shift
        guard (0...127).contains(pitch) else { return nil }
        self.pitch = pitch
    }

    public var name: String {
        Self.sharpNames[((pitch % 12) + 12) % 12] + String(pitch / 12 - 1)
    }

    /// The name without the octave: "C", "F#". How lessons talk to beginners.
    public var letter: String {
        Self.sharpNames[((pitch % 12) + 12) % 12]
    }

    public var description: String { name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let text = try c.decode(String.self)
        guard let note = NoteName(text) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not a note name: \"\(text)\" (expected e.g. C4, F#3, Bb4)")
        }
        self = note
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(name)
    }
}
