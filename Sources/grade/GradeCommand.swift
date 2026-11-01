import ArgumentParser
import Foundation
import PianoGraderCore

@main
struct Grade: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "grade",
        abstract: "Grade a piano take against a reference MIDI passage.",
        discussion: """
        Examples:
          grade --ref lesson12a.mid --take take.mid --rubric Rubrics/beginner.md
          grade --ref lesson12a.mid --live --label fail
          grade --ref lesson12a.mid --keys
          grade check --fixtures fixtures
          grade transcribe song.mid -o song.musicxml
          grade listen take.wav --truth take.mid --guide lesson12a.mid
          grade eval --environment dry,room --markdown report.md
        """,
        subcommands: [Score.self, CheckFixtures.self, Transcribe.self, Listen.self, Calibrate.self, Evaluate.self],
        defaultSubcommand: Score.self
    )
}

enum Verdict: String, Codable, ExpressibleByArgument, CaseIterable {
    case pass, fail
}

/// Loads a rubric file, or the built-in beginner rubric when none is given.
func loadRubric(_ path: String?) throws -> Rubric {
    guard let path else { return .beginner }
    return try Rubric.load(url: URL(fileURLWithPath: path))
}

struct Score: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "score",
        abstract: "Grade one take: from a file, played live over MIDI, or typed on the computer keyboard."
    )

    @Option(help: "Reference MIDI file for the passage.")
    var ref: String

    @Option(help: "Recorded take to grade (.mid).")
    var take: String?

    @Flag(help: "Record the take live from every connected MIDI input (macOS).")
    var live = false

    @Flag(help: "Play the take on the computer keyboard (musical typing, as in Logic or Ableton).")
    var keys = false

    @Option(help: "With --keys: octave of the note on the A key (4 = middle C).")
    var octave: Int = 4

    @Flag(help: "With --keys: don't play sound.")
    var noSound = false

    @Option(help: "Rubric file: Markdown with YAML front matter, or YAML. Defaults to the built-in beginner rubric.")
    var rubric: String?

    @Option(help: "Target tempo in bpm, overriding the rubric and the reference file.")
    var tempo: Double?

    @Option(help: "Where to save a live or typed take. Defaults to takes/<reference>-<time>.mid.")
    var out: String?

    @Option(help: "Write the JSON report to this path, or '-' for stdout only.")
    var json: String?

    @Option(help: "Your own verdict for this take (pass or fail). Saves the take as a fixture for 'grade check'.")
    var label: Verdict?

    @Option(help: "Fixture directory used with --label.")
    var fixtures: String = "fixtures"

    @Option(help: "Seconds of silence after the last note that end a live take.")
    var silence: Double = 2

    func validate() throws {
        let sources = [take != nil, live, keys].filter { $0 }.count
        if sources != 1 {
            throw ValidationError("Give exactly one of --take <file>, --live or --keys.")
        }
    }

    func run() throws {
        var rubricValue = try loadRubric(rubric)
        if let tempo { rubricValue.targetBPM = tempo }

        let refURL = URL(fileURLWithPath: ref)
        let reference = try MIDIFile.read(url: refURL)

        let takeURL: URL
        if live {
            takeURL = try recordLiveTake(reference: refURL)
        } else if keys {
            let notes = try KeyboardRecorder(octave: octave, sound: !noSound).record()
            takeURL = try saveTake(notes, reference: refURL)
        } else {
            takeURL = URL(fileURLWithPath: take!)
        }

        let takeSequence = try MIDIFile.read(url: takeURL)
        let report = Grader(rubric: rubricValue).grade(reference: reference, take: takeSequence)

        if json != "-" {
            print(ReportPrinter.text(report, rubric: rubricValue, reference: refURL, take: takeURL))
        }
        if let json {
            let data = try ReportPrinter.json(report)
            if json == "-" {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write("\n".data(using: .utf8)!)
            } else {
                try data.write(to: URL(fileURLWithPath: json))
            }
        }

        if let label {
            let store = FixtureStore(directory: URL(fileURLWithPath: fixtures))
            let rubricURL = rubric.map { URL(fileURLWithPath: $0) }
            let saved = try store.save(reference: refURL, take: takeURL, rubric: rubricURL, label: label)
            let agrees = (label == .pass) == report.passed
            print("Saved fixture \(saved.lastPathComponent): you said \(label.rawValue), grader said \(report.passed ? "pass" : "fail")\(agrees ? "" : "  ← disagreement")")
        }
    }

    private func recordLiveTake(reference: URL) throws -> URL {
        #if canImport(CoreMIDI)
        let recorder = LiveRecorder(silenceSeconds: silence)
        let notes = try recorder.record()
        return try saveTake(notes, reference: reference)
        #else
        throw ValidationError("Live capture needs CoreMIDI, which is only available on Apple platforms.")
        #endif
    }

    private func saveTake(_ notes: [NoteEvent], reference: URL) throws -> URL {
        guard !notes.isEmpty else { throw ValidationError("No notes were played.") }
        let url = URL(fileURLWithPath: out ?? Self.defaultTakePath(reference: reference))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try MIDIFile.write(notes: notes).write(to: url)
        print("Saved take: \(url.path)")
        return url
    }

    static func defaultTakePath(reference: URL) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = reference.deletingPathExtension().lastPathComponent
        return "takes/\(stem)-\(formatter.string(from: Date())).mid"
    }
}

struct CheckFixtures: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Re-grade every saved fixture and report how often the grader agrees with your labels."
    )

    @Option(help: "Fixture directory.")
    var fixtures: String = "fixtures"

    @Option(help: "Minimum share of fixtures where grader and label must agree (the milestone gate is 0.9).")
    var gate: Double = 0.9

    func run() throws {
        let store = FixtureStore(directory: URL(fileURLWithPath: fixtures))
        let all = try store.all()
        guard !all.isEmpty else {
            print("No fixtures in \(fixtures). Save some with: grade --ref <file> --live --label pass|fail")
            return
        }

        var agree = 0
        var flagKinds: [String: Int] = [:]
        print("fixture".padding(toLength: 34, withPad: " ", startingAt: 0) + "label  grader  first flag")
        for fixture in all {
            let rubric = try fixture.rubric()
            let report = try Grader(rubric: rubric).grade(referenceURL: fixture.referenceURL, takeURL: fixture.takeURL)
            let ok = (fixture.meta.label == .pass) == report.passed
            if ok { agree += 1 }
            for f in report.flags { flagKinds[f.kind.rawValue, default: 0] += 1 }
            let name = fixture.directory.lastPathComponent.padding(toLength: 34, withPad: " ", startingAt: 0)
            let label = fixture.meta.label.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)
            let grader = (report.passed ? "pass" : "fail").padding(toLength: 8, withPad: " ", startingAt: 0)
            print("\(name)\(label)\(grader)\(report.flags.first?.message ?? "-")\(ok ? "" : "  ← disagree")")
        }

        let share = Double(agree) / Double(all.count)
        print("")
        print("Agreement: \(agree)/\(all.count) (\(Int((share * 100).rounded()))%), gate \(Int((gate * 100).rounded()))%")
        let kinds = ["wrongPitch", "missed", "extra", "early", "late"]
        print("Mistake kinds flagged: " + kinds.map { "\($0) \(flagKinds[$0, default: 0])" }.joined(separator: ", "))
        if share < gate { throw ExitCode.failure }
    }
}
