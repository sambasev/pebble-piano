import ArgumentParser
import Foundation
import PianoGraderCore

/// Writes a MIDI file out as MusicXML, the same transcription PianoPad shows on screen.
struct Transcribe: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe a MIDI file into MusicXML (sixteenth-note grid, piano staves)."
    )

    @Argument(help: "MIDI file to transcribe.")
    var midi: String

    @Option(name: .shortAndLong, help: "Where to write the MusicXML. Defaults to the MIDI path with .musicxml; '-' prints it.")
    var out: String?

    @Option(help: "Key signature as fifths (−7 … 7), overriding the file and the estimate.")
    var fifths: Int?

    @Option(help: "With hands split by pitch: lowest pitch on the treble staff (60 = middle C).")
    var split: Int = 60

    @Option(help: "Also draw the score as SVG to this path, as PianoPad shows it.")
    var svg: String?

    @Option(help: "With --svg: page width in points.")
    var width: Double = 900

    @Option(help: "With --svg: draw the playhead at this many quarter notes from the start.")
    var cursor: Double?

    @Option(parsing: .upToNextOption, help: "With --svg and --cursor: pitches the guide is waiting for (MIDI numbers).")
    var expected: [Int] = []

    @Option(parsing: .upToNextOption, help: "With --svg and --cursor: wrong pitches to mark (MIDI numbers).")
    var wrong: [Int] = []

    @Option(help: "With --svg: show every note starting before this many quarter notes as played (green).")
    var playedUntil: Double?

    @Option(parsing: .upToNextOption, help: "With --svg: measure numbers to tint as graded mistakes.")
    var mistakes: [Int] = []

    func run() throws {
        let url = URL(fileURLWithPath: midi)
        let sequence = try MIDIFile.read(url: url)
        let options = Transcriber.Options(splitPitch: split, key: fifths.map { KeySignature(fifths: $0) })
        let score = Transcriber(options: options).transcribe(sequence, title: sequence.title ?? url.deletingPathExtension().lastPathComponent)
        if let svg {
            let layout = ScoreLayout(score: score, width: width)
            let played = playedUntil.map { until in
                sequence.notes.filter { $0.onsetBeats < until - 1e-6 && $0.channel != 9 }.map { PlayedNote(quarter: $0.onsetBeats, pitch: $0.pitch) }
            } ?? []
            let overlay = ScoreOverlay(cursorQuarter: cursor, expected: Set(expected), played: played, wrong: Set(wrong),
                                       mistakeMeasures: mistakes.isEmpty ? nil : Set(mistakes))
            try Data(ScoreRenderer(layout: layout).render(overlay).svg().utf8).write(to: URL(fileURLWithPath: svg))
        }
        let xml = MusicXMLWriter.write(score)
        if out == "-" {
            print(xml, terminator: "")
            return
        }
        let target = out.map { URL(fileURLWithPath: $0) } ?? url.deletingPathExtension().appendingPathExtension("musicxml")
        try Data(xml.utf8).write(to: target)
        let clefs = score.staves.map(\.rawValue).joined(separator: " + ")
        print("Wrote \(target.path): \(score.measures.count) measures, \(clefs), key \(score.key.fifths) fifths, \(score.timeSignature.numerator)/\(score.timeSignature.denominator).")
    }
}
