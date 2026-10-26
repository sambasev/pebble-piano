import ArgumentParser
import Foundation
import PianoGraderCore

/// Runs the microphone note detector over a recording: prints what it heard, or scores it
/// against the MIDI of what was played (record the piano's MIDI out and a mic at the same time).
struct Listen: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "listen",
        abstract: "Detect piano notes in a WAV recording, as PianoPad's microphone input does."
    )

    @Argument(help: "WAV recording (mono or stereo, 16/24/32-bit PCM or 32-bit float).")
    var wav: String

    @Option(help: "MIDI of what was really played, to measure accuracy and latency.")
    var truth: String?

    @Option(help: "Score the player follows (MIDI): the detector expects each chord in turn, as in wait mode.")
    var guide: String?

    @Option(help: "Seconds of audio before the MIDI's first note (if the recording started earlier).")
    var offset: Double = 0

    @Option(help: .hidden) var evalDelay: Double?
    @Option(help: .hidden) var maxWindow: Double?
    @Option(help: .hidden) var iterations: Int?
    @Option(help: .hidden) var neighbourPenalty: Double?
    @Option(help: .hidden) var otherPenalty: Double?
    @Option(help: .hidden) var freePlayPenalty: Double?
    @Option(help: .hidden) var expectedThreshold: Double?
    @Option(help: .hidden) var neighbourThreshold: Double?
    @Option(help: .hidden) var otherThreshold: Double?
    @Option(help: .hidden) var minimumRise: Double?
    @Option(help: .hidden) var rolloff: Double?
    @Option(help: .hidden) var lowCut: Double?
    @Option(help: .hidden) var fluxLow: Double?
    @Option(help: .hidden) var onsetSensitivity: Double?
    @Option(help: .hidden) var tuning: Double?
    @Option(help: .hidden) var relativePenalty: Double?
    @Option(help: .hidden) var relativeThreshold: Double?
    @Option(help: .hidden) var noiseVeto: Double?
    @Option(help: .hidden) var levelRise: Float?
    @Option(help: .hidden) var bassGuard: Double?
    @Option(help: .hidden) var neighbourDominance: Double?
    @Option(help: "Calibration recording (quiet, then C4, D4, E4 one at a time) to measure the piano first.")
    var calibration: String?
    @Option(help: .hidden) var calibrationNotes: String?

    private var settings: PianoNoteDetector.Settings {
        var s = PianoNoteDetector.Settings()
        if let evalDelay { s.evaluationDelay = evalDelay }
        if let maxWindow { s.maxWindow = maxWindow }
        if let iterations { s.iterations = iterations }
        if let neighbourPenalty { s.neighbourPenalty = neighbourPenalty }
        if let otherPenalty { s.otherPenalty = otherPenalty }
        if let freePlayPenalty { s.freePlayPenalty = freePlayPenalty }
        if let expectedThreshold { s.expectedThreshold = expectedThreshold }
        if let neighbourThreshold { s.neighbourThreshold = neighbourThreshold }
        if let otherThreshold { s.otherThreshold = otherThreshold }
        if let minimumRise { s.minimumRise = minimumRise }
        if let rolloff { s.partialRolloff = rolloff }
        if let lowCut { s.micLowCut = lowCut }
        if let fluxLow { s.fluxLowFrequency = fluxLow }
        if let onsetSensitivity { s.onsetSensitivity = onsetSensitivity }
        if let tuning { s.tuningCents = tuning }
        if let relativePenalty { s.relativePenalty = relativePenalty }
        if let relativeThreshold { s.relativeThreshold = relativeThreshold }
        if let noiseVeto { s.noiseVeto = noiseVeto }
        if let levelRise { s.levelRise = levelRise }
        if let bassGuard { s.bassGuardThreshold = bassGuard }
        if let neighbourDominance { s.neighbourDominance = neighbourDominance }
        s.profile = profile
        return s
    }

    private var profile: PianoProfile? {
        guard let calibration, let audio = try? WAVFile.read(url: URL(fileURLWithPath: calibration)) else { return nil }
        let notes = calibrationNotes.map { $0.split(separator: ",").compactMap { Int($0) } } ?? PianoCalibration.defaultNotes
        switch PianoCalibration.analyse(audio.samples, sampleRate: audio.sampleRate, notes: notes) {
        case .success(let p): return p
        case .failure(let problem):
            FileHandle.standardError.write(Data("calibration failed: \(problem)\n".utf8))
            return nil
        }
    }

    func run() throws {
        let audio = try WAVFile.read(url: URL(fileURLWithPath: wav))
        let guideChords = try guide.map { path -> [ChordEvent] in
            let notes = try MIDIFile.read(url: URL(fileURLWithPath: path)).notes.map { shifted($0) }
            return ChordGrouping.group(notes, window: 0.05)
        }

        guard let truth else {
            let detector = PianoNoteDetector(sampleRate: audio.sampleRate, settings: settings)
            var position = 0
            var guideIndex = 0
            while position < audio.samples.count {
                let now = Double(position) / audio.sampleRate
                if let g = guideChords {
                    while guideIndex < g.count && g[guideIndex].onset < now - 0.15 { guideIndex += 1 }
                    detector.expected = guideIndex < g.count ? g[guideIndex].pitches : []
                }
                let end = min(audio.samples.count, position + 256)
                for e in detector.process(Array(audio.samples[position..<end])) {
                    let name = PitchName.of(e.pitch).padding(toLength: 4, withPad: " ", startingAt: 0)
                    let kind = e.kind == .on ? "on " : "off"
                    let after = String(format: "%+.0f", (e.reportedAt - e.time) * 1000)
                    let confidence = e.kind == .on ? String(format: "  conf %.2f", e.confidence) : ""
                    print(String(format: "%8.3f", e.time) + "  \(kind) \(name)  (reported \(after) ms)\(confidence)")
                }
                position = end
            }
            return
        }

        let truthNotes = try MIDIFile.read(url: URL(fileURLWithPath: truth)).notes.map { shifted($0) }
        let r = DetectorEvaluation.run(audio: audio.samples, sampleRate: audio.sampleRate, truth: truthNotes, guide: guideChords, settings: settings)
        print(String(format: "notes played %d, detected %d, matched %d", r.truthCount, r.detectedCount, r.matched))
        print(String(format: "precision %.3f  recall %.3f  F1 %.3f", r.precision, r.recall, r.f1))
        print(String(format: "latency from key strike: median %.0f ms, 95th %.0f ms (detector only; add audio buffering)",
                     r.latency(percentile: 0.5) * 1000, r.latency(percentile: 0.95) * 1000))
        if !r.missed.isEmpty {
            print("missed: " + r.missed.prefix(12).map { "\(PitchName.of($0.pitch))@" + String(format: "%.2f", $0.time) }.joined(separator: " "))
        }
        if !r.extra.isEmpty {
            print("extra:  " + r.extra.prefix(12).map { "\(PitchName.of($0.pitch))@" + String(format: "%.2f", $0.time) }.joined(separator: " "))
        }
    }

    private func shifted(_ n: NoteEvent) -> NoteEvent {
        var m = n
        m.onset += offset
        m.offset += offset
        return m
    }
}

/// Measures a piano from a calibration recording and prints (or saves) the profile.
struct Calibrate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Measure a piano from a recording: a moment of quiet, then C4, D4 and E4, one at a time."
    )

    @Argument(help: "WAV recording of the calibration notes.")
    var wav: String

    @Option(help: "The notes played, in order (MIDI numbers, comma separated).")
    var notes: String = "60,62,64"

    @Option(help: "Write the profile as JSON here.")
    var output: String?

    func run() throws {
        let audio = try WAVFile.read(url: URL(fileURLWithPath: wav))
        let pitches = notes.split(separator: ",").compactMap { Int($0) }
        switch PianoCalibration.analyse(audio.samples, sampleRate: audio.sampleRate, notes: pitches) {
        case .failure(let problem):
            throw ValidationError("\(problem)")
        case .success(let profile):
            for a in profile.anchors {
                let levels = a.partialLevels.prefix(10).map { String(format: "%.0f", $0) }.joined(separator: " ")
                print("\(PitchName.of(a.pitch).padding(toLength: 4, withPad: " ", startingAt: 0)) "
                      + String(format: "%+.1f cents  B %.5f  partials dB: ", a.cents, a.inharmonicity) + levels)
            }
            print(String(format: "room background %.1f dBFS", 20 * log10(max(Double(profile.noiseLevel), 1e-9))))
            if let output {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(profile).write(to: URL(fileURLWithPath: output))
            }
        }
    }
}
