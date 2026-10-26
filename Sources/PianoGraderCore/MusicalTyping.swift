import Foundation

/// Computer-keyboard-as-piano mapping, matching Logic's and Ableton's "musical typing":
///
///     W E   T Y U   O P        black keys
///    A S D F G H J K L ; '     white keys (A = C)
///
/// Z / X shift the octave down / up, C / V lower / raise the velocity.
public struct MusicalTyping: Sendable {
    /// Semitone offset from the current octave's C for each note key.
    public static let noteKeys: [Character: Int] = [
        "a": 0, "w": 1, "s": 2, "e": 3, "d": 4, "f": 5, "t": 6, "g": 7, "y": 8,
        "h": 9, "u": 10, "j": 11, "k": 12, "o": 13, "l": 14, "p": 15, ";": 16, "'": 17,
    ]

    public enum Action: Equatable, Sendable {
        case note(pitch: Int, velocity: Int)
        case octave(Int)
        case velocity(Int)
        case finish
        case cancel
        case ignored
    }

    /// Octave number of the note on the A key, in MIDI naming (C4 = 60 = middle C).
    public private(set) var octave: Int
    public private(set) var velocity: Int

    public static let minOctave = -1
    public static let maxOctave = 8
    public static let velocityStep = 20

    public init(octave: Int = 4, velocity: Int = 80) {
        self.octave = max(Self.minOctave, min(Self.maxOctave, octave))
        self.velocity = max(1, min(127, velocity))
    }

    /// MIDI pitch of the A key.
    public var basePitch: Int { (octave + 1) * 12 }

    /// Handles one byte typed in the terminal. Uppercase letters (Caps Lock) behave like lowercase.
    public mutating func handle(_ byte: UInt8) -> Action {
        switch byte {
        case 0x0D, 0x0A: return .finish // Return
        case 0x1B: return .cancel        // Escape
        default: break
        }
        let ch = Character(Unicode.Scalar(byte)).lowercased().first ?? " "
        if let offset = Self.noteKeys[ch] {
            let pitch = basePitch + offset
            return (0...127).contains(pitch) ? .note(pitch: pitch, velocity: velocity) : .ignored
        }
        switch ch {
        case "z":
            octave = max(Self.minOctave, octave - 1)
            return .octave(octave)
        case "x":
            octave = min(Self.maxOctave, octave + 1)
            return .octave(octave)
        case "c":
            velocity = max(1, velocity - Self.velocityStep)
            return .velocity(velocity)
        case "v":
            velocity = min(127, velocity + Self.velocityStep)
            return .velocity(velocity)
        default:
            return .ignored
        }
    }

    /// Static keyboard map for the terminal, labelled for the current octave.
    public var diagram: String {
        func name(_ offset: Int) -> String { PitchName.of(basePitch + offset) }
        func cell(_ s: String, _ width: Int) -> String { s.padding(toLength: width, withPad: " ", startingAt: 0) }
        // Black keys sit between white keys; gaps where there is no black key (E–F, B–C).
        let blackKeys: [(Character, Int)?] = [
            ("w", 1), ("e", 3), nil, ("t", 6), ("y", 8), ("u", 10), nil, ("o", 13), ("p", 15), nil,
        ]
        let whiteKeys: [(Character, Int)] = [
            ("a", 0), ("s", 2), ("d", 4), ("f", 5), ("g", 7), ("h", 9), ("j", 11), ("k", 12), ("l", 14), (";", 16), ("'", 17),
        ]
        let w = 6
        var blackKeyRow = "   ", blackNameRow = "   "
        for slot in blackKeys {
            if let (key, offset) = slot {
                blackKeyRow += cell(" [\(key.uppercased())]", w)
                blackNameRow += cell(" \(name(offset))", w)
            } else {
                blackKeyRow += cell("", w)
                blackNameRow += cell("", w)
            }
        }
        var whiteKeyRow = "", whiteNameRow = ""
        for (key, offset) in whiteKeys {
            whiteKeyRow += cell(" [\(key.uppercased())]", w)
            whiteNameRow += cell(" \(name(offset))", w)
        }
        return [
            blackKeyRow, blackNameRow, whiteKeyRow, whiteNameRow, "",
            "[Z]/[X] octave down/up   [C]/[V] velocity down/up   [Return] finish   [Esc] cancel",
        ].map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
         .joined(separator: "\n")
    }
}
