import Foundation

/// A pitch as it is written: a letter, an alteration and an octave.
/// C4 is middle C (MIDI 60); B♯3 and C4 are the same key written differently.
public struct SpelledPitch: Codable, Equatable, Hashable, Sendable {
    /// Letter index: 0 = C, 1 = D, … 6 = B.
    public var step: Int
    /// Semitones: −1 flat, 0 natural, +1 sharp.
    public var alter: Int
    /// Scientific octave of the letter (B♯3 is octave 3 even though it sounds as C4).
    public var octave: Int

    public init(step: Int, alter: Int, octave: Int) {
        self.step = step
        self.alter = alter
        self.octave = octave
    }

    static let letters = ["C", "D", "E", "F", "G", "A", "B"]
    static let naturalPitchClass = [0, 2, 4, 5, 7, 9, 11]

    public var letter: String { Self.letters[step] }

    /// Position on the staff in letter steps: C4 = 28, D4 = 29 … (octave × 7 + step).
    public var diatonicIndex: Int { octave * 7 + step }

    /// The MIDI note this spelling sounds as.
    public var midi: Int { (octave + 1) * 12 + Self.naturalPitchClass[step] + alter }

    /// "E♭4", "F♯3", "C4".
    public var name: String {
        let sign = alter == 0 ? "" : String(repeating: alter > 0 ? "♯" : "♭", count: abs(alter))
        return letter + sign + String(octave)
    }
}

extension KeySignature {
    /// Order sharps are added in (F C G D A E B) as letter indices.
    private static let sharpOrder = [3, 0, 4, 1, 5, 2, 6]

    /// Alteration the key signature gives a letter (+1 sharp, −1 flat, 0 natural).
    public func alter(forStep step: Int) -> Int {
        if fifths > 0 {
            return Self.sharpOrder.prefix(fifths).contains(step) ? 1 : 0
        } else if fifths < 0 {
            return Self.sharpOrder.reversed().prefix(-fifths).contains(step) ? -1 : 0
        }
        return 0
    }

    /// Pitch classes of the major scale with this signature.
    public var scalePitchClasses: Set<Int> {
        Set((0..<7).map { step in (SpelledPitch.naturalPitchClass[step] + alter(forStep: step) + 12) % 12 })
    }

    /// Writes a MIDI note the way it reads most naturally in this key: notes in the key
    /// take the key's spelling; other notes use the fewest accidentals relative to the key,
    /// preferring naturals, then sharps in sharp keys (and C major) and flats in flat keys.
    public func spell(_ midi: Int) -> SpelledPitch {
        let pitchClass = ((midi % 12) + 12) % 12
        var best: (cost: Int, tie: Int, spelling: SpelledPitch)? = nil
        for step in 0..<7 {
            for alter in -1...1 {
                guard (SpelledPitch.naturalPitchClass[step] + alter + 12) % 12 == pitchClass else { continue }
                let keyAlter = self.alter(forStep: step)
                let cost = abs(alter - keyAlter)
                // Lower tie is better: naturals first, then the key's direction.
                let tie: Int
                if alter == 0 { tie = 0 }
                else if (fifths >= 0) == (alter > 0) { tie = 1 }
                else { tie = 2 }
                // The octave belongs to the letter: B♯ sits below the C it sounds as.
                let octave = (midi - SpelledPitch.naturalPitchClass[step] - alter) / 12 - 1
                let candidate = SpelledPitch(step: step, alter: alter, octave: octave)
                if best == nil || (cost, tie) < (best!.cost, best!.tie) {
                    best = (cost, tie, candidate)
                }
            }
        }
        return best!.spelling
    }

    /// Guesses the key signature from the notes: the major scale (−6 … +6 fifths) that
    /// covers the most note time, preferring fewer accidentals on a tie.
    public static func estimate(from notes: [NoteEvent]) -> KeySignature {
        guard !notes.isEmpty else { return .cMajor }
        var weight = [Double](repeating: 0, count: 12)
        for n in notes {
            let length = max(0.25, (n.offsetBeats ?? n.onsetBeats + 1) - n.onsetBeats)
            weight[((n.pitch % 12) + 12) % 12] += length
        }
        var best = KeySignature.cMajor
        var bestScore = -Double.infinity
        for fifths in -6...6 {
            let key = KeySignature(fifths: fifths)
            let inScale = key.scalePitchClasses
            let score = (0..<12).reduce(0.0) { $0 + (inScale.contains($1) ? weight[$1] : -weight[$1]) }
            // Small penalty per accidental so C beats G when F/F♯ never appears.
            let adjusted = score - Double(abs(fifths)) * 1e-6
            if adjusted > bestScore {
                bestScore = adjusted
                best = key
            }
        }
        return best
    }
}
