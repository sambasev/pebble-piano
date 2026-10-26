import Foundation

/// Writes a `Score` as MusicXML 4.0 (score-partwise): one "Piano" part on one or two
/// staves, so MuseScore, Finale, Dorico and similar programs can open the transcription.
public enum MusicXMLWriter {
    public static func write(_ score: Score) -> String {
        let divisions = Score.sixteenthsPerQuarter // one division = one sixteenth
        var x = XMLBuilder()
        x.raw("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>")
        x.raw("<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\">")
        x.open("score-partwise", attributes: ["version": "4.0"])
        x.open("work")
        x.leaf("work-title", score.title)
        x.close("work")
        x.open("identification")
        x.open("encoding")
        x.leaf("software", "PianoPad")
        x.close("encoding")
        x.close("identification")
        x.open("part-list")
        x.open("score-part", attributes: ["id": "P1"])
        x.leaf("part-name", "Piano")
        x.close("score-part")
        x.close("part-list")

        x.open("part", attributes: ["id": "P1"])
        for (index, measure) in score.measures.enumerated() {
            x.open("measure", attributes: ["number": String(measure.number)])
            if index == 0 {
                x.open("attributes")
                x.leaf("divisions", String(divisions))
                x.open("key")
                x.leaf("fifths", String(score.key.fifths))
                x.leaf("mode", score.key.isMinor ? "minor" : "major")
                x.close("key")
                x.open("time")
                x.leaf("beats", String(score.timeSignature.numerator))
                x.leaf("beat-type", String(score.timeSignature.denominator))
                x.close("time")
                if score.staves.count > 1 { x.leaf("staves", String(score.staves.count)) }
                for (i, clef) in score.staves.enumerated() {
                    x.open("clef", attributes: score.staves.count > 1 ? ["number": String(i + 1)] : [:])
                    x.leaf("sign", clef == .treble ? "G" : "F")
                    x.leaf("line", clef == .treble ? "2" : "4")
                    x.close("clef")
                }
                x.close("attributes")

                let bpm = Int(score.tempoBPM.rounded())
                x.open("direction", attributes: ["placement": "above"])
                x.open("direction-type")
                x.open("metronome")
                x.leaf("beat-unit", "quarter")
                x.leaf("per-minute", String(bpm))
                x.close("metronome")
                x.close("direction-type")
                if score.staves.count > 1 { x.leaf("staff", "1") }
                x.empty("sound", attributes: ["tempo": String(bpm)])
                x.close("direction")
            }

            for staff in score.staves.indices {
                if staff > 0 {
                    x.open("backup")
                    x.leaf("duration", String(measure.length))
                    x.close("backup")
                }
                // Voices 1 and 5 are the conventional numbering for the two piano staves.
                let voice = staff == 0 ? "1" : "5"
                for event in measure.events(onStaff: staff) {
                    if event.isRest {
                        x.open("note")
                        x.empty("rest", attributes: event.isMeasureRest ? ["measure": "yes"] : [:])
                        x.leaf("duration", String(event.duration))
                        x.leaf("voice", voice)
                        if !event.isMeasureRest {
                            x.leaf("type", event.type.rawValue)
                            for _ in 0..<event.dots { x.empty("dot") }
                        }
                        if score.staves.count > 1 { x.leaf("staff", String(staff + 1)) }
                        x.close("note")
                        continue
                    }
                    for (i, note) in event.notes.enumerated() {
                        x.open("note")
                        if i > 0 { x.empty("chord") }
                        x.open("pitch")
                        x.leaf("step", note.spelled.letter)
                        if note.spelled.alter != 0 { x.leaf("alter", String(note.spelled.alter)) }
                        x.leaf("octave", String(note.spelled.octave))
                        x.close("pitch")
                        x.leaf("duration", String(event.duration))
                        if note.tieStop { x.empty("tie", attributes: ["type": "stop"]) }
                        if note.tieStart { x.empty("tie", attributes: ["type": "start"]) }
                        x.leaf("voice", voice)
                        x.leaf("type", event.type.rawValue)
                        for _ in 0..<event.dots { x.empty("dot") }
                        if let accidental = note.accidental { x.leaf("accidental", accidentalName(accidental)) }
                        if score.staves.count > 1 { x.leaf("staff", String(staff + 1)) }
                        if i == 0 {
                            for (level, beam) in event.beams.enumerated() {
                                x.open("beam", attributes: ["number": String(level + 1)], inline: beam.rawValue)
                            }
                        }
                        if note.tieStart || note.tieStop {
                            x.open("notations")
                            if note.tieStop { x.empty("tied", attributes: ["type": "stop"]) }
                            if note.tieStart { x.empty("tied", attributes: ["type": "start"]) }
                            x.close("notations")
                        }
                        x.close("note")
                    }
                }
            }

            if index == score.measures.count - 1 {
                x.open("barline", attributes: ["location": "right"])
                x.leaf("bar-style", "light-heavy")
                x.close("barline")
            }
            x.close("measure")
        }
        x.close("part")
        x.close("score-partwise")
        return x.text
    }

    static func accidentalName(_ alter: Int) -> String {
        switch alter {
        case 1: return "sharp"
        case -1: return "flat"
        case 2: return "double-sharp"
        case -2: return "flat-flat"
        default: return "natural"
        }
    }
}

/// Indented XML with escaped text and attribute values.
struct XMLBuilder {
    private(set) var text = ""
    private var depth = 0

    mutating func raw(_ line: String) { text += line + "\n" }

    mutating func open(_ name: String, attributes: [String: String] = [:]) {
        line("<\(name)\(Self.attributes(attributes))>")
        depth += 1
    }

    /// An element with attributes and text on one line.
    mutating func open(_ name: String, attributes: [String: String], inline value: String) {
        line("<\(name)\(Self.attributes(attributes))>\(Self.escape(value))</\(name)>")
    }

    mutating func close(_ name: String) {
        depth -= 1
        line("</\(name)>")
    }

    mutating func leaf(_ name: String, _ value: String) {
        line("<\(name)>\(Self.escape(value))</\(name)>")
    }

    mutating func empty(_ name: String, attributes: [String: String] = [:]) {
        line("<\(name)\(Self.attributes(attributes))/>")
    }

    private mutating func line(_ s: String) {
        text += String(repeating: "  ", count: max(0, depth)) + s + "\n"
    }

    private static func attributes(_ attributes: [String: String]) -> String {
        attributes.keys.sorted().map { " \($0)=\"\(escape(attributes[$0]!))\"" }.joined()
    }

    static func escape(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(c)
            }
        }
        return out
    }
}
