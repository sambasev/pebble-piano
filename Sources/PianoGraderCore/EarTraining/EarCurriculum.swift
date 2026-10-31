import Foundation

public struct EarStageID: Hashable, Codable, Sendable, Identifiable {
    public let level: Int
    public let stage: Int
    public var id: String { "\(level).\(stage)" }
    public init(level: Int, stage: Int) { self.level = level; self.stage = stage }
    public static let first = EarStageID(level: 1, stage: 1)
    public var next: EarStageID? {
        guard (1...8).contains(level), (1...3).contains(stage) else { return nil }
        if stage < 3 { return EarStageID(level: level, stage: stage + 1) }
        return level < 8 ? EarStageID(level: level + 1, stage: 1) : nil
    }
}

public struct EarStage: Identifiable, Sendable {
    public let id: EarStageID
    public let title: String
    public let detail: String
}

public struct EarLevel: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let detail: String
    public let stages: [EarStage]
}

public struct EarAnswer: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public init(id: String, title: String) { self.id = id; self.title = title }
}

/// A question has separate reference and solution audio, and never needs UI or audio frameworks.
public struct EarQuestion: Identifiable, Sendable {
    public let id: String
    public let stage: EarStageID
    public let prompt: String
    public let context: String
    public let correctAnswer: EarAnswer
    public let choices: [EarAnswer]
    public let stimulus: [NoteEvent]
    public let reference: [NoteEvent]
    public let referenceLabel: String
    public let solution: [NoteEvent]
    public let explanation: String
    public let solutionLabel: String
}

enum EarPattern: Sendable { case note, chord, ascending, descending, harmonic, melody, progression, rootless }

struct EarTemplate: Sendable {
    let answer: EarAnswer
    let voices: [[Int]]
    let pattern: EarPattern
    let explanation: String
    var subject = ""
}

public enum EarCurriculum {
    public static let levels: [EarLevel] = [
        level(1, "Natural notes", "Build a pitch vocabulary, starting with three notes.", [
            ("Three notes", "Recognize C, D, and E in octave 4."),
            ("Five notes", "Add F and G to your note vocabulary."),
            ("Seven notes", "Recognize every natural note: C through B.")]),
        level(2, "Sharps & flats", "Hear the spaces between the natural notes.", [
            ("Accidentals", "Recognize the five black-key pitch classes."),
            ("Chromatic octave", "Mix all twelve pitches in octave 4."),
            ("Across octaves", "Recognize pitch classes across octaves 3, 4, and 5.")]),
        level(3, "Basic chords", "Recognize the color of root-position triads.", [
            ("Major & minor", "Hear the difference a third makes."),
            ("Diminished", "Add the tense diminished triad."),
            ("Augmented", "Distinguish all four basic triad qualities.")]),
        level(4, "Inversions & sevenths", "Separate chord color from bass position.", [
            ("Triad inversions", "Identify root position, first inversion, or second inversion."),
            ("Seventh qualities", "Recognize five essential seventh-chord qualities."),
            ("Seventh inversions", "Identify all four positions of nonsymmetric seventh chords.")]),
        level(5, "Intervals & melody", "Hear pitch relationships and short melodic shapes.", [
            ("Ascending intervals", "Recognize each interval from a minor second to an octave."),
            ("Mixed intervals", "Recognize ascending, descending, and simultaneous intervals."),
            ("Melodic patterns", "Identify three-to-five-note patterns using major scale degrees.")]),
        level(6, "Functional harmony", "Recognize cadences and the movement of harmony.", [
            ("Cadences", "Identify authentic, plagal, half, and deceptive cadences."),
            ("ii–V–I", "Hear major and minor ii–V resolutions."),
            ("Turnarounds", "Compare diatonic, secondary-dominant, and diminished turnarounds.")]),
        level(7, "Jazz extensions", "Recognize extended harmony across keys and voicings.", [
            ("Ninth chords", "Identify major, minor, and dominant ninths."),
            ("Elevenths & thirteenths", "Recognize minor elevenths and major/dominant thirteenths."),
            ("Open voicings", "Identify extended qualities in spread and inverted voicings.")]),
        level(8, "Advanced jazz", "Hear altered colors, substitutions, and changing tonal centers.", [
            ("Rootless alterations", "Identify dominant ♭9, ♯9, ♯11, and ♭13 voicings after a bass cue."),
            ("Substitutions", "Distinguish ii–V–I, tritone, backdoor, and diminished approaches."),
            ("Modulating ii–V–I", "Track the destination of a second ii–V–I in a new key.")])
    ]

    private static func level(_ id: Int, _ title: String, _ detail: String,
                              _ stages: [(String, String)]) -> EarLevel {
        EarLevel(id: id, title: title, detail: detail, stages: stages.enumerated().map {
            EarStage(id: EarStageID(level: id, stage: $0.offset + 1), title: $0.element.0, detail: $0.element.1)
        })
    }

    public static func stage(_ id: EarStageID) -> EarStage? {
        levels.first { $0.id == id.level }?.stages.first { $0.id == id }
    }

    public static let pitchNames = ["C", "C♯ / D♭", "D", "D♯ / E♭", "E", "F",
                                    "F♯ / G♭", "G", "G♯ / A♭", "A", "A♯ / B♭", "B"]

    public static func pitchName(_ pitch: Int) -> String { pitchNames[((pitch % 12) + 12) % 12] }

    static func templates(_ id: EarStageID) -> [EarTemplate] {
        guard stage(id) != nil else { return [] }
        func t(_ key: String, _ title: String, _ notes: [[Int]], _ pattern: EarPattern,
               _ explanation: String, subject: String = "") -> EarTemplate {
            EarTemplate(answer: EarAnswer(id: key, title: title), voices: notes, pattern: pattern,
                        explanation: explanation, subject: subject)
        }
        if id.level <= 2 {
            let pitches: [Int]
            if id.level == 1 {
                pitches = id.stage == 1 ? [0, 2, 4] : id.stage == 2 ? [0, 2, 4, 5, 7] : [0, 2, 4, 5, 7, 9, 11]
            } else { pitches = id.stage == 1 ? [1, 3, 6, 8, 10] : Array(0..<12) }
            return pitches.map { pc in
                t("note.\(pc)", pitchName(pc), [[pc]], .note,
                  "This is \(pitchName(pc)). Octaves share the same pitch class. Sharps and flats joined by / are two names for the same piano key.")
            }
        }
        let triads: [(String, String, [Int])] = [
            ("major", "Major", [0, 4, 7]), ("minor", "Minor", [0, 3, 7]),
            ("diminished", "Diminished", [0, 3, 6]), ("augmented", "Augmented", [0, 4, 8])]
        let sevenths: [(String, String, [Int])] = [
            ("maj7", "Major 7", [0, 4, 7, 11]), ("min7", "Minor 7", [0, 3, 7, 10]),
            ("dom7", "Dominant 7", [0, 4, 7, 10]), ("halfDim7", "Half-diminished 7", [0, 3, 6, 10]),
            ("dim7", "Diminished 7", [0, 3, 6, 9])]
        let extensions: [(String, String, [Int])] = [
            ("maj9", "Major 9", [0, 4, 7, 11, 14]), ("min9", "Minor 9", [0, 3, 7, 10, 14]),
            ("dom9", "Dominant 9", [0, 4, 7, 10, 14]), ("min11", "Minor 11", [0, 3, 10, 14, 17]),
            ("maj13", "Major 13", [0, 4, 11, 14, 21]), ("dom13", "Dominant 13", [0, 4, 10, 14, 21])]
        if id.level == 3 {
            return triads.prefix(id.stage + 1).map { key, name, notes in
                t(key, name, [notes], .chord, "\(name) triad: semitones above the root are \(notes.map(String.init).joined(separator: ", ")).")
            }
        }
        if id.level == 4 {
            if id.stage == 2 {
                return sevenths.map { key, name, notes in
                    t(key, name, [notes], .chord, "\(name): semitones above the root are \(notes.map(String.init).joined(separator: ", ")).")
                }
            }
            let chords = id.stage == 1 ? Array(triads.prefix(2)) : Array(sevenths.prefix(4))
            let names = ["Root position", "First inversion", "Second inversion", "Third inversion"]
            return chords.flatMap { _, quality, notes in
                (0..<notes.count).map { inversion in
                    let voiced = Array(notes.dropFirst(inversion)) + notes.prefix(inversion).map { $0 + 12 }
                    return t("inversion.\(inversion)", names[inversion], [voiced], .chord,
                             "\(quality), \(names[inversion].lowercased()). The bass is the \(["root", "third", "fifth", "seventh"][inversion]) of the chord.", subject: quality)
                }
            }
        }
        if id.level == 5 {
            if id.stage < 3 {
                let names = ["Minor 2nd", "Major 2nd", "Minor 3rd", "Major 3rd", "Perfect 4th", "Tritone",
                             "Perfect 5th", "Minor 6th", "Major 6th", "Minor 7th", "Major 7th", "Octave"]
                let patterns: [EarPattern] = id.stage == 1 ? [.ascending] : [.ascending, .descending, .harmonic]
                return names.enumerated().flatMap { offset, name in
                    patterns.map { pattern in
                        t("interval.\(offset + 1)", name, [[0], [offset + 1]], pattern,
                          "\(name): \(offset + 1) semitones between the two pitches.")
                    }
                }
            }
            let patterns = [[1, 2, 3], [1, 3, 5], [1, 5, 3], [1, 3, 2],
                            [1, 2, 3, 5], [1, 3, 5, 3], [1, 5, 4, 3], [1, 3, 2, 5],
                            [1, 2, 3, 2, 1], [1, 3, 5, 3, 1], [1, 5, 4, 2, 1], [1, 3, 4, 2, 1]]
            let scale = [0, 2, 4, 5, 7, 9, 11]
            return patterns.map { degrees in
                let label = degrees.map(String.init).joined(separator: "–")
                return t("melody.\(label)", label, degrees.map { [scale[$0 - 1]] }, .melody,
                         "Major scale degrees \(label). Degree 1 is the tonic; sing the pattern against the key reference.")
            }
        }
        if id.level == 6 {
            if id.stage == 1 {
                return [
                    t("authentic", "Authentic · V–I", [[7, 11, 14, 17], [0, 4, 7]], .progression, "The dominant resolves to the tonic: V–I."),
                    t("plagal", "Plagal · IV–I", [[5, 9, 12], [0, 4, 7]], .progression, "The subdominant resolves to the tonic: IV–I."),
                    t("half", "Half · ii–V", [[2, 5, 9], [7, 11, 14, 17]], .progression, "The phrase rests on the dominant: ii–V."),
                    t("deceptive", "Deceptive · V–vi", [[7, 11, 14, 17], [9, 12, 16]], .progression, "The dominant moves to the relative minor instead of I: V–vi.")]
            }
            if id.stage == 2 {
                return [
                    t("major251", "Major ii–V–I", [[2, 5, 9, 12], [7, 11, 14, 17], [0, 4, 7, 11]], .progression,
                      "Minor 7 → dominant 7 → major 7: the major ii–V–I."),
                    t("minor251", "Minor iiø–V–i", [[2, 5, 8, 12], [7, 11, 14, 17], [0, 3, 7, 10]], .progression,
                      "Half-diminished ii → dominant V → minor tonic. The lowered fifth of ii and minor tonic distinguish this from the major pattern.")]
            }
            return [
                t("diatonic", "I–vi–ii–V", [[0, 4, 7, 11], [9, 12, 16, 19], [2, 5, 9, 12], [7, 11, 14, 17]], .progression,
                  "A diatonic turnaround: major I, minor vi, minor ii, dominant V."),
                t("secondary", "I–VI7–ii–V", [[0, 4, 7, 11], [9, 13, 16, 19], [2, 5, 9, 12], [7, 11, 14, 17]], .progression,
                  "VI7 is the secondary dominant of ii. Listen for its raised third before ii."),
                t("passingDim", "I–♯i°7–ii–V", [[0, 4, 7, 11], [1, 4, 7, 10], [2, 5, 9, 12], [7, 11, 14, 17]], .progression,
                  "A chromatically rising bass connects I to ii through a passing diminished seventh.")]
        }
        if id.level == 7 {
            let chords = id.stage == 1 ? Array(extensions.prefix(3)) : id.stage == 2 ? Array(extensions.suffix(3)) : extensions
            return chords.map { key, name, notes in
                t(key, name, [notes], .chord, "\(name): semitone formula \(notes.map(String.init).joined(separator: ", ")). The reference supplies the root; listen for the third, seventh, and upper color tones.")
            }
        }
        if id.stage == 1 {
            return [
                t("domFlat9", "Dominant ♭9", [[4, 10, 13, 19]], .rootless, "Rootless 3–♭7–♭9–5. The ♭9 sits one semitone above the root's octave."),
                t("domSharp9", "Dominant ♯9", [[4, 10, 15, 19]], .rootless, "Rootless 3–♭7–♯9–5. Hear the major third below the contrasting sharp ninth."),
                t("domSharp11", "Dominant ♯11", [[4, 10, 14, 18]], .rootless, "Rootless 3–♭7–9–♯11. The sharp eleventh adds a tritone above the root."),
                t("domFlat13", "Dominant ♭13", [[4, 10, 14, 20]], .rootless, "Rootless 3–♭7–9–♭13. Compare the lowered thirteenth with the sharp-eleventh example.")]
        }
        let tonic = [0, 4, 11, 14, 19]
        if id.stage == 2 {
            return [
                t("jazz251", "ii9–V13–Imaj9", [[2, 5, 12, 16, 21], [7, 11, 17, 21, 28], tonic], .progression,
                  "The conventional major ii–V–I, with ninth and thirteenth colors."),
                t("tritone", "ii9–♭II9–Imaj9", [[2, 5, 12, 16, 21], [1, 5, 11, 15, 20], tonic], .progression,
                  "The tritone substitute ♭II7 shares the third/seventh tritone of V7. The bass descends chromatically to I."),
                t("backdoor", "iv9–♭VII13–Imaj9", [[5, 8, 15, 19, 24], [10, 14, 20, 24, 31], tonic], .progression,
                  "The minor iv moves through ♭VII7 to I: a backdoor resolution."),
                t("diminishedApproach", "IVmaj9–♯iv°7–Imaj9", [[5, 9, 16, 19, 24], [6, 9, 12, 15], tonic], .progression,
                  "A raised-fourth diminished seventh resolves to I; hear the chromatic approach rather than a dominant seventh.")]
        }
        let destinations = [(2, "up2", "Up a major 2nd"), (3, "upMinor3", "Up a minor 3rd"),
                            (5, "up4", "Up a perfect 4th"), (7, "up5", "Up a perfect 5th")]
        let first = [[2, 5, 12, 16], [7, 11, 17, 20], tonic]
        return destinations.map { shift, key, name in
            let second = [[2, 5, 12, 16], [7, 11, 17, 20], tonic].map { $0.map { $0 + shift } }
            return t(key, name, first + second, .progression,
                     "Two major ii–V–I sequences. The second tonic moves \(name.lowercased()) from the first. Track the bass resolution and the tonic's major seventh.")
        }
    }
}
