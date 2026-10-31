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
/// signatures aren't read yet) and a time signature from the bars' most common length.
public enum ScoreWriter {
    public static func write(_ bars: [BarMerge.Bar], title: String, tempoBPM: Double = 80) -> ImportedPiece {
        let timeSignature = timeSignature(of: bars)
        let barLength = timeSignature.numerator * 16 / timeSignature.denominator  // sixteenths
        let clefs = [clef(bars, .upper), clef(bars, .lower)]

        var measures: [ScoreMeasure] = []
        var notes: [NoteEvent] = []
        var fingering: [Int] = []
        var start = 0  // sixteenths from the start of the piece
        for (i, bar) in bars.enumerated() {
            var events: [ScoreEvent] = []
            var longest = 0
            for (staffIndex, staffName) in SystemReading.StaffName.allCases.enumerated() {
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
            // A short first bar is a pickup; otherwise every bar has the metre's length.
            let length = i == 0 && longest < barLength ? longest : barLength
            measures.append(ScoreMeasure(number: i + 1, startSixteenth: start, length: length,
                                         events: events.sorted { ($0.staff, $0.start) < ($1.staff, $1.start) }))
            start += length
        }

        let score = Score(title: title, tempoBPM: tempoBPM, timeSignature: timeSignature, key: KeySignature(fifths: 0),
                          staves: clefs, measures: measures)
        let midi = MIDIFile.write(notes: notes, tempoBPM: tempoBPM, timeSignature: timeSignature)
        return ImportedPiece(score: score, midi: midi, fingering: fingering, musicXML: MusicXMLWriter.write(score))
    }

    /// The most common bar length, as quarter notes over 4 (or eighths over 8 when it isn't a
    /// whole number of quarters, as in 6/8). 4/4 when there are no notes.
    static func timeSignature(of bars: [BarMerge.Bar]) -> TimeSignature {
        var counts: [Int: Int] = [:]  // length in eighths → bars
        for bar in bars {
            let eighths = SystemReading.StaffName.allCases.map { s in
                Int((bar.notes(s).reduce(0) { $0 + $1.note.quarters } * 2).rounded())
            }.max() ?? 0
            if eighths > 0 { counts[eighths, default: 0] += 1 }
        }
        guard let eighths = counts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) })?.key else {
            return TimeSignature(numerator: 4, denominator: 4)
        }
        return eighths % 2 == 0 ? TimeSignature(numerator: eighths / 2, denominator: 4)
                                : TimeSignature(numerator: eighths, denominator: 8)
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
