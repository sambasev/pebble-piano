import ArgumentParser
import Foundation
import PianoGraderCore

/// Evaluates and compares audio-to-MIDI piano transcription models and methods.
struct Evaluate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eval",
        abstract: "Evaluate and benchmark audio-to-MIDI transcription models against ground truth."
    )

    @Option(help: "Directory containing WAV + .truth.mid test cases (defaults to Fixtures/transcription).")
    var fixtures: String?

    @Option(help: "Run evaluation on a single specific test case base path (without extension).")
    var `case`: String?

    @Option(help: "Acoustic environments for synthetic suite: dry, room, noisy, or all.")
    var environment: String = "dry,room"

    @Option(help: "Models to evaluate: nmf-score, nmf-free, baseline-peak, ablations, all.")
    var models: String = "all"

    @Option(help: "Onset matching tolerance in seconds.")
    var tolerance: Double = 0.12

    @Flag(inversion: .prefixedNo, help: "Automatically detect and align time offset between audio and MIDI.")
    var autoAlign: Bool = true

    @Option(help: "Write evaluation summary as a Markdown report to this file.")
    var markdown: String?

    @Option(help: "Write detailed evaluation results as JSON to this file.")
    var json: String?

    @Flag(help: "Print fine-grained breakdowns by pitch register.")
    var detail: Bool = false

    func run() throws {
        var testCases: [AudioBenchmarkCorpus.TestCase] = []

        // 1. Load user fixtures if available
        let fixtureDir = fixtures ?? "Fixtures/transcription"
        if let specificCase = `case` {
            if let loaded = try loadCase(basePath: specificCase) {
                testCases.append(loaded)
            } else {
                throw ValidationError("Could not find test case files for \(specificCase)")
            }
        } else if FileManager.default.fileExists(atPath: fixtureDir) {
            let loaded = try loadCasesFromDirectory(fixtureDir)
            testCases.append(contentsOf: loaded)
        }

        // 2. Load synthetic suite if no specific single case requested
        if `case` == nil {
            let envs: [AudioBenchmarkCorpus.Environment]
            if environment.lowercased() == "all" {
                envs = AudioBenchmarkCorpus.Environment.allCases
            } else {
                envs = environment.split(separator: ",").compactMap { AudioBenchmarkCorpus.Environment(rawValue: String($0).trimmingCharacters(in: .whitespaces)) }
            }
            let synthetic = AudioBenchmarkCorpus.standardSuite(environments: envs.isEmpty ? [.dry, .room] : envs)
            testCases.append(contentsOf: synthetic)
        }

        guard !testCases.isEmpty else {
            throw ValidationError("No test cases found to evaluate. Add files to Fixtures/transcription/ or run synthetic suite.")
        }

        print("Running transcription evaluation over \(testCases.count) test case(s)...")

        // 3. Instantiate requested models
        let modelConfigs = selectModels(models)

        // 4. Run evaluation
        var modelResults: [(modelName: String, results: [DetectorEvaluation.Result])] = []

        for (name, factory) in modelConfigs {
            var caseResults: [DetectorEvaluation.Result] = []
            for testCase in testCases {
                let transcriber = factory(testCase.sampleRate)
                let result = DetectorEvaluation.evaluate(
                    transcriber: transcriber,
                    audio: testCase.audio,
                    sampleRate: testCase.sampleRate,
                    truth: testCase.truthNotes,
                    guide: testCase.guideChords,
                    tolerance: tolerance,
                    autoAlign: autoAlign
                )
                caseResults.append(result)
            }
            modelResults.append((name, caseResults))
        }

        // 5. Aggregate and print results
        renderTerminalTable(modelResults)

        if detail {
            renderRegisterDetail(modelResults)
        }

        // 6. Save reports if requested
        if let markdownPath = markdown {
            try generateMarkdownReport(modelResults, to: markdownPath)
            print("Saved Markdown report to \(markdownPath)")
        }

        if let jsonPath = json {
            try generateJSONReport(modelResults, to: jsonPath)
            print("Saved JSON report to \(jsonPath)")
        }
    }

    private func selectModels(_ spec: String) -> [(String, (Double) -> AudioTranscriber)] {
        let requested = spec.lowercased().split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let isAll = requested.contains("all")

        var list: [(String, (Double) -> AudioTranscriber)] = []

        if isAll || requested.contains("nmf-score") {
            list.append(("Score-Informed NMF", { rate in ScoreInformedTranscriber(sampleRate: rate) }))
        }
        if isAll || requested.contains("nmf-free") {
            list.append(("Free-Play NMF (Unguided)", { rate in FreePlayTranscriber(sampleRate: rate) }))
        }
        if isAll || requested.contains("baseline-peak") {
            list.append(("Spectral Peak (Baseline)", { rate in SpectralPeakTranscriber(sampleRate: rate) }))
        }
        if isAll || requested.contains("ablations") {
            // Low-latency setting (30ms evaluation delay)
            list.append(("NMF (Fast 30ms Delay)", { rate in
                var s = PianoNoteDetector.Settings()
                s.evaluationDelay = 0.03
                return AblationTranscriber(name: "NMF (30ms Delay)", description: "Low latency 30ms evaluation delay", sampleRate: rate, settings: s)
            }))
            // High-precision setting (5 iterations, lighter CPU)
            list.append(("NMF (5 Iterations)", { rate in
                var s = PianoNoteDetector.Settings()
                s.iterations = 5
                return AblationTranscriber(name: "NMF (5 Iterations)", description: "Faster compute 5 NMF iterations", sampleRate: rate, settings: s)
            }))
        }

        return list
    }

    private func loadCase(basePath: String) throws -> AudioBenchmarkCorpus.TestCase? {
        let cleanBase = basePath.replacingOccurrences(of: ".wav", with: "").replacingOccurrences(of: ".truth.mid", with: "")
        let wavUrl = URL(fileURLWithPath: cleanBase + ".wav")
        let truthUrl = URL(fileURLWithPath: cleanBase + ".truth.mid")
        let guideUrl = URL(fileURLWithPath: cleanBase + ".guide.mid")

        guard FileManager.default.fileExists(atPath: wavUrl.path),
              FileManager.default.fileExists(atPath: truthUrl.path) else {
            return nil
        }

        let audio = try WAVFile.read(url: wavUrl)
        let truthNotes = try MIDIFile.read(url: truthUrl).notes
        let guideChords: [ChordEvent]
        if FileManager.default.fileExists(atPath: guideUrl.path) {
            let guideNotes = try MIDIFile.read(url: guideUrl).notes
            guideChords = ChordGrouping.group(guideNotes, window: 0.05)
        } else {
            guideChords = ChordGrouping.group(truthNotes, window: 0.05)
        }

        return AudioBenchmarkCorpus.TestCase(
            name: (cleanBase as NSString).lastPathComponent,
            description: "User fixture: \((cleanBase as NSString).lastPathComponent)",
            audio: audio.samples,
            sampleRate: audio.sampleRate,
            truthNotes: truthNotes,
            guideChords: guideChords,
            environment: .dry
        )
    }

    private func loadCasesFromDirectory(_ path: String) throws -> [AudioBenchmarkCorpus.TestCase] {
        let url = URL(fileURLWithPath: path)
        let items = try FileManager.default.contentsOfDirectory(atPath: path)
        let wavFiles = items.filter { $0.hasSuffix(".wav") && !$0.contains(".cal.") }

        var cases: [AudioBenchmarkCorpus.TestCase] = []
        for wav in wavFiles {
            let base = (wav as NSString).deletingPathExtension
            let fullBase = url.appendingPathComponent(base).path
            if let tc = try loadCase(basePath: fullBase) {
                cases.append(tc)
            }
        }
        return cases
    }

    private func renderTerminalTable(_ data: [(modelName: String, results: [DetectorEvaluation.Result])]) {
        func pad(_ s: String, _ len: Int, alignRight: Bool = false) -> String {
            if s.count >= len { return String(s.prefix(len)) }
            let spaces = String(repeating: " ", count: len - s.count)
            return alignRight ? spaces + s : s + spaces
        }

        print("\n=============================== EVALUATION SUMMARY ===============================")
        let header = "\(pad("Model / Method", 25)) │ \(pad("Prec", 6, alignRight: true)) │ \(pad("Recall", 6, alignRight: true)) │ \(pad("F1", 6, alignRight: true)) │ \(pad("Lat p50", 9, alignRight: true)) │ \(pad("Lat p95", 9, alignRight: true)) │ \(pad("CleanPass", 9, alignRight: true)) │ \(pad("RTF", 6, alignRight: true))"
        print(header)
        print(String(repeating: "─", count: 26) + "┼" +
              String(repeating: "─", count: 8) + "┼" +
              String(repeating: "─", count: 8) + "┼" +
              String(repeating: "─", count: 8) + "┼" +
              String(repeating: "─", count: 11) + "┼" +
              String(repeating: "─", count: 11) + "┼" +
              String(repeating: "─", count: 11) + "┼" +
              String(repeating: "─", count: 8))

        for (name, results) in data {
            let totalTruth = results.reduce(0) { $0 + $1.truthCount }
            let totalDetected = results.reduce(0) { $0 + $1.detectedCount }
            let totalMatched = results.reduce(0) { $0 + $1.matched }

            let precision = totalDetected == 0 ? 1.0 : Double(totalMatched) / Double(totalDetected)
            let recall = totalTruth == 0 ? 1.0 : Double(totalMatched) / Double(totalTruth)
            let f1 = precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall)

            let allLatencies = results.flatMap(\.latencies).sorted()
            let p50 = allLatencies.isEmpty ? 0 : allLatencies[Int(Double(allLatencies.count - 1) * 0.5)] * 1000
            let p95 = allLatencies.isEmpty ? 0 : allLatencies[Int(Double(allLatencies.count - 1) * 0.95)] * 1000

            let cleanTruth = results.reduce(0) { $0 + $1.cleanTruthCount }
            let cleanMatched = results.reduce(0) { $0 + $1.cleanMatchedCount }
            let cleanPass = cleanTruth == 0 ? 100.0 : (Double(cleanMatched) / Double(cleanTruth)) * 100.0

            let totalAudioDuration = results.reduce(0.0) { $0 + $1.audioDuration }
            let totalProcessing = results.reduce(0.0) { $0 + $1.processingTime }
            let rtf = totalAudioDuration > 0 ? totalProcessing / totalAudioDuration : 0

            let row = "\(pad(name, 25)) │ \(pad(String(format: "%.3f", precision), 6, alignRight: true)) │ \(pad(String(format: "%.3f", recall), 6, alignRight: true)) │ \(pad(String(format: "%.3f", f1), 6, alignRight: true)) │ \(pad(String(format: "%.0f ms", p50), 9, alignRight: true)) │ \(pad(String(format: "%.0f ms", p95), 9, alignRight: true)) │ \(pad(String(format: "%.1f%%", cleanPass), 9, alignRight: true)) │ \(pad(String(format: "%.2fx", rtf), 6, alignRight: true))"
            print(row)
        }
        print("===================================================================================\n")
    }

    private func renderRegisterDetail(_ data: [(modelName: String, results: [DetectorEvaluation.Result])]) {
        print("\n--- Pitch Register Breakdown (F1 / Accuracy) ---")
        for (name, results) in data {
            print("\n[\(name)]")
            for reg in ["Bass (A0–B2)", "Mid (C3–B4)", "Treble (C5–C8)"] {
                var truth = 0, matched = 0, detected = 0
                for r in results {
                    if let b = r.registerBreakdowns.first(where: { $0.name == reg }) {
                        truth += b.truthCount
                        matched += b.matched
                        detected += b.detectedCount
                    }
                }
                let p = detected == 0 ? 1.0 : Double(matched) / Double(detected)
                let rec = truth == 0 ? 1.0 : Double(matched) / Double(truth)
                let f1 = p + rec == 0 ? 0 : 2 * p * rec / (p + rec)
                let label = reg.padding(toLength: 16, withPad: " ", startingAt: 0)
                print("  \(label): Truth \(truth) | Matched \(matched) | Precision \(String(format: "%.3f", p)) | Recall \(String(format: "%.3f", rec)) | F1 \(String(format: "%.3f", f1))")
            }
        }
    }

    private func generateMarkdownReport(_ data: [(modelName: String, results: [DetectorEvaluation.Result])], to path: String) throws {
        var md = "# Audio-to-MIDI Transcription Evaluation Report\n\n"
        md += "Evaluated on \(data.first?.results.count ?? 0) test cases across acoustic conditions.\n\n"
        md += "## Overall Model Comparison\n\n"
        md += "| Model / Method | Precision | Recall | F1 Score | Latency (p50) | Latency (p95) | Clean Acceptance | RTF (Compute) |\n"
        md += "|---|---|---|---|---|---|---|---|\n"

        for (name, results) in data {
            let totalTruth = results.reduce(0) { $0 + $1.truthCount }
            let totalDetected = results.reduce(0) { $0 + $1.detectedCount }
            let totalMatched = results.reduce(0) { $0 + $1.matched }

            let precision = totalDetected == 0 ? 1.0 : Double(totalMatched) / Double(totalDetected)
            let recall = totalTruth == 0 ? 1.0 : Double(totalMatched) / Double(totalTruth)
            let f1 = precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall)

            let allLatencies = results.flatMap(\.latencies).sorted()
            let p50 = allLatencies.isEmpty ? 0 : allLatencies[Int(Double(allLatencies.count - 1) * 0.5)] * 1000
            let p95 = allLatencies.isEmpty ? 0 : allLatencies[Int(Double(allLatencies.count - 1) * 0.95)] * 1000

            let cleanTruth = results.reduce(0) { $0 + $1.cleanTruthCount }
            let cleanMatched = results.reduce(0) { $0 + $1.cleanMatchedCount }
            let cleanPass = cleanTruth == 0 ? 100.0 : (Double(cleanMatched) / Double(cleanTruth)) * 100.0

            let totalAudioDuration = results.reduce(0.0) { $0 + $1.audioDuration }
            let totalProcessing = results.reduce(0.0) { $0 + $1.processingTime }
            let rtf = totalAudioDuration > 0 ? totalProcessing / totalAudioDuration : 0

            md += String(format: "| **%@** | %.3f | %.3f | **%.3f** | %.0f ms | %.0f ms | %.1f%% | %.2fx |\n",
                         name, precision, recall, f1, p50, p95, cleanPass, rtf)
        }

        md += "\n> **RTF (Real-Time Factor)**: Audio processing time ÷ duration. Values < 0.1x indicate fast real-time CPU headroom.\n"
        try Data(md.utf8).write(to: URL(fileURLWithPath: path))
    }

    private func generateJSONReport(_ data: [(modelName: String, results: [DetectorEvaluation.Result])], to path: String) throws {
        var jsonDict: [String: Any] = [:]
        var modelsArr: [[String: Any]] = []

        for (name, results) in data {
            let totalTruth = results.reduce(0) { $0 + $1.truthCount }
            let totalDetected = results.reduce(0) { $0 + $1.detectedCount }
            let totalMatched = results.reduce(0) { $0 + $1.matched }

            let precision = totalDetected == 0 ? 1.0 : Double(totalMatched) / Double(totalDetected)
            let recall = totalTruth == 0 ? 1.0 : Double(totalMatched) / Double(totalTruth)
            let f1 = precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall)

            let allLatencies = results.flatMap(\.latencies).sorted()
            let p50 = allLatencies.isEmpty ? 0 : allLatencies[Int(Double(allLatencies.count - 1) * 0.5)] * 1000
            let p95 = allLatencies.isEmpty ? 0 : allLatencies[Int(Double(allLatencies.count - 1) * 0.95)] * 1000

            modelsArr.append([
                "name": name,
                "truth_count": totalTruth,
                "detected_count": totalDetected,
                "matched_count": totalMatched,
                "precision": precision,
                "recall": recall,
                "f1": f1,
                "latency_p50_ms": p50,
                "latency_p95_ms": p95
            ])
        }

        jsonDict["models"] = modelsArr
        let jsonData = try JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys])
        try jsonData.write(to: URL(fileURLWithPath: path))
    }
}
