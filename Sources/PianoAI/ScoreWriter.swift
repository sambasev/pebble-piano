import Foundation
import PianoGraderCore

/// A piece read from a book, ready for the app: the score to engrave, reference MIDI to grade
/// against (one track per staff), finger numbers for the top staff, and MusicXML to export.
public struct ImportedPiece: Sendable {
    public var score: Score
    public var midi: Data
    /// One per top-staff note in score order; 0 where the book prints no finger number.
    public var fingering: [Int]
    public var musicXML: String
}

/// Turns merged bars into a `Score`, reference MIDI and MusicXML. Assumes C major (key
/// signatures aren't read yet) and a common time signature from the bars' lengths.
public enum ScoreWriter {
    /// `oneStaff`: a right-hand piece, written on the upper staff alone (the bars' lower staff is
    /// left out).
    public static func write(_ bars: [BarMerge.Bar], title: String, tempoBPM: Double = 80,
                             oneStaff: Bool = false) -> ImportedPiece {
        let timeSignature = timeSignature(of: bars)
        let barLength = timeSignature.numerator * 16 / timeSignature.denominator  // sixteenths
        let staffNames: [SystemReading.StaffName] = oneStaff ? [.upper] : SystemReading.StaffName.allCases
        let clefs = staffNames.map { clef(bars, $0) }

        var measures: [ScoreMeasure] = []
        var notes: [NoteEvent] = []
        var fingering: [Int] = []
        var start = 0  // sixteenths from the start of the piece
        for (i, bar) in bars.enumerated() {
            var events: [ScoreEvent] = []
            var longest = 0
            for (staffIndex, staffName) in staffNames.enumerated() {
                var at = 0
                var altered: Set<Int> = []  // letter steps given a sharp or flat earlier in this bar
                let staffNotes = bar.notes(staffName)
                for n in staffNotes {
                    let length = max(1, Int((n.note.quarters * 4).rounded()))
                    let type = noteType(n.note.duration)
                    if n.note.rest {
                        events.append(ScoreEvent(staff: staffIndex, start: at, duration: length, type: type,
                                                 dots: n.note.dotted ? 1 : 0, notes: [],
                                                 isMeasureRest: staffNotes.count == 1 && length >= barLength))
                    } else {
                        let midi = StaffPitch.midi(clef: n.clef, position: n.note.position, accidental: n.note.accidental)
                        let step = StaffPitch.bottomLine(n.clef) + n.note.position
                        let octave = Int(floor(Double(step) / 7))
                        let alter = n.note.accidental == .sharp ? 1 : n.note.accidental == .flat ? -1 : 0
                        // C major: a natural is only worth printing to cancel an earlier sharp or flat.
                        let printed: Int?
                        switch n.note.accidental {
                        case .none: printed = nil
                        case .natural: printed = altered.contains(step) ? 0 : nil
                        case .sharp, .flat: printed = alter
                        }
                        if alter != 0 { altered.insert(step) } else if n.note.accidental == .natural { altered.remove(step) }
                        let note = ScoreNote(midi: midi, spelled: SpelledPitch(step: step - octave * 7, alter: alter, octave: octave),
                                             accidental: printed)
                        events.append(ScoreEvent(staff: staffIndex, start: at, duration: length, type: type,
                                                 dots: n.note.dotted ? 1 : 0, notes: [note]))
                        let beats = Double(start + at) / 4, quarters = n.note.quarters
                        let held = quarters - min(0.125, quarters / 4)  // a little short, so repeats re-strike
                        notes.append(NoteEvent(pitch: midi, onset: beats * 60 / tempoBPM, offset: (beats + held) * 60 / tempoBPM,
                                               onsetBeats: beats, offsetBeats: beats + held, channel: staffIndex, track: staffIndex))
                        if staffIndex == 0 { fingering.append(n.note.finger ?? 0) }
                    }
                    at += length
                }
                if staffNotes.isEmpty {  // nothing read for this staff yet (a skipped bar): a bar's rest
                    events.append(ScoreEvent(staff: staffIndex, start: 0, duration: barLength, type: .whole, dots: 0,
                                             notes: [], isMeasureRest: true))
                    at = barLength
                }
                longest = max(longest, at)
            }
            // A short first bar is a pickup; a bar that runs over the metre (a page with no
            // barlines, say) keeps its whole length rather than inventing an odd metre.
            let length = i == 0 && longest < barLength ? longest : max(barLength, longest)
            measures.append(ScoreMeasure(number: i + 1, startSixteenth: start, length: length,
                                         events: events.sorted { ($0.staff, $0.start) < ($1.staff, $1.start) }))
            start += length
        }

        let score = Score(title: title, tempoBPM: tempoBPM, timeSignature: timeSignature, key: KeySignature(fifths: 0),
                          staves: clefs, measures: measures)
        let midi = MIDIFile.write(notes: notes, tempoBPM: tempoBPM, timeSignature: timeSignature)
        return ImportedPiece(score: score, midi: midi, fingering: fingering, musicXML: MusicXMLWriter.write(score))
    }

    /// The metres a piece is given: anything else a page seems to have (17/4, 11/8, …) is far more
    /// likely a misread bar or a page without barlines than a real metre. Six eighths is 3/4 or
    /// 6/8, told apart by where the notes fall (see `isCompound`).
    static let commonMetres: [Int: TimeSignature] = [  // bar length in eighths → metre
        3: TimeSignature(numerator: 3, denominator: 8),
        4: TimeSignature(numerator: 2, denominator: 4),
        5: TimeSignature(numerator: 5, denominator: 8),
        6: TimeSignature(numerator: 3, denominator: 4),
        7: TimeSignature(numerator: 7, denominator: 8),
        8: TimeSignature(numerator: 4, denominator: 4),
        9: TimeSignature(numerator: 9, denominator: 8),
        10: TimeSignature(numerator: 5, denominator: 4),
        12: TimeSignature(numerator: 12, denominator: 8),
    ]

    /// The common metre matching the most bars. 4/4 when no bar has a common length.
    static func timeSignature(of bars: [BarMerge.Bar]) -> TimeSignature {
        var counts: [Int: Int] = [:]  // length in eighths → bars
        for bar in bars {
            let eighths = eighthsLong(bar)
            if commonMetres[eighths] != nil { counts[eighths, default: 0] += 1 }
        }
        guard let eighths = counts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key else {
            return TimeSignature(numerator: 4, denominator: 4)
        }
        if eighths == 6, isCompound(bars.filter { eighthsLong($0) == 6 }) {
            return TimeSignature(numerator: 6, denominator: 8)
        }
        return commonMetres[eighths]!
    }

    static func eighthsLong(_ bar: BarMerge.Bar) -> Int {
        SystemReading.StaffName.allCases.map { s in
            Int((bar.notes(s).reduce(0) { $0 + $1.note.quarters } * 2).rounded())
        }.max() ?? 0
    }

    /// Whether six-eighth bars move in two beats of three eighths (6/8: a note starts on the 4th
    /// eighth) rather than three beats of two (3/4: a note starts on the 5th).
    static func isCompound(_ bars: [BarMerge.Bar]) -> Bool {
        var onFourth = 0, onFifth = 0
        for bar in bars {
            for s in SystemReading.StaffName.allCases {
                var at = 0.0  // in eighths
                for n in bar.notes(s) {
                    if at == 3 { onFourth += 1 } else if at == 4 { onFifth += 1 }
                    at += n.note.quarters * 2
                }
            }
        }
        return onFourth > onFifth
    }

    static func clef(_ bars: [BarMerge.Bar], _ staff: SystemReading.StaffName) -> Clef {
        let c = bars.lazy.compactMap { $0.notes(staff).first?.clef }.first ?? (staff == .upper ? .treble : .bass)
        return c == .treble ? .treble : .bass
    }

    static func noteType(_ d: SystemReading.Duration) -> NoteType {
        switch d {
        case .whole: return .whole
        case .half: return .half
        case .quarter: return .quarter
        case .eighth: return .eighth
        case .sixteenth: return .sixteenth
        }
    }
}
