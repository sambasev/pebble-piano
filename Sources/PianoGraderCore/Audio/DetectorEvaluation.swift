import Foundation

/// Minimal WAV reader: PCM 16/24/32-bit integer or 32-bit float, any channel count (mixed to mono).
public enum WAVFile {
    public struct Audio {
        public var sampleRate: Double
        public var samples: [Float]
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case notWAV, unsupported(String)
        public var description: String {
            switch self {
            case .notWAV: return "Not a RIFF/WAVE file."
            case .unsupported(let what): return "Unsupported WAV: \(what)."
            }
        }
    }

    public static func read(url: URL) throws -> Audio { try parse(Data(contentsOf: url)) }

    public static func parse(_ data: Data) throws -> Audio {
        let b = [UInt8](data)
        func u32(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 }
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        guard b.count >= 12, String(bytes: b[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: b[8..<12], encoding: .ascii) == "WAVE" else { throw Error.notWAV }
        var i = 12
        var format = 0, channels = 1, rate = 44100, bits = 16
        var dataRange: Range<Int>? = nil
        while i + 8 <= b.count {
            let id = String(bytes: b[i..<i + 4], encoding: .ascii) ?? ""
            let size = u32(i + 4)
            let body = i + 8
            if id == "fmt " {
                format = u16(body)
                channels = max(1, u16(body + 2))
                rate = u32(body + 4)
                bits = u16(body + 14)
                if format == 0xFFFE && size >= 26 { format = u16(body + 24) } // extensible
            } else if id == "data" {
                // A recording that was never closed has a zero size: its data runs to the end.
                dataRange = body..<(size == 0 ? b.count : min(b.count, body + size))
                if size == 0 { break }
            }
            i = body + size + (size & 1)
        }
        guard let range = dataRange else { throw Error.unsupported("no data chunk") }
        let bytesPerSample = bits / 8
        guard (format == 1 && [2, 3, 4].contains(bytesPerSample)) || (format == 3 && bits == 32) else {
            throw Error.unsupported("format \(format), \(bits)-bit")
        }
        let frameBytes = bytesPerSample * channels
        let frames = range.count / frameBytes
        var samples = [Float](repeating: 0, count: frames)
        for f in 0..<frames {
            var mix: Float = 0
            for c in 0..<channels {
                let o = range.lowerBound + f * frameBytes + c * bytesPerSample
                let v: Float
                switch (format, bytesPerSample) {
                case (3, 4): v = Float(bitPattern: UInt32(u32(o)))
                case (1, 2): v = Float(Int16(truncatingIfNeeded: u16(o))) / 32768
                case (1, 3): v = Float(Int32(truncatingIfNeeded: (Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16) << 8) >> 8) / 8_388_608
                default: v = Float(Int32(truncatingIfNeeded: u32(o))) / 2_147_483_648
                }
                mix += v
            }
            samples[f] = mix / Float(channels)
        }
        return Audio(sampleRate: Double(rate), samples: samples)
    }
}

/// Runs a transcription model over an audio recording and scores it against ground truth MIDI.
public enum DetectorEvaluation {
    /// Fine-grained score breakdown for a specific subset of notes (e.g. register or dynamic).
    public struct Breakdown: Sendable, Codable {
        public var name: String
        public var truthCount: Int
        public var detectedCount: Int
        public var matched: Int
        public var precision: Double { detectedCount == 0 ? 1 : Double(matched) / Double(detectedCount) }
        public var recall: Double { truthCount == 0 ? 1 : Double(matched) / Double(truthCount) }
        public var f1: Double { precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall) }
        public var medianLatencyMs: Double

        public init(name: String, truthCount: Int, detectedCount: Int, matched: Int, medianLatencyMs: Double) {
            self.name = name
            self.truthCount = truthCount
            self.detectedCount = detectedCount
            self.matched = matched
            self.medianLatencyMs = medianLatencyMs
        }
    }

    /// Full quantitative evaluation results across all metrics.
    public struct Result: Sendable {
        public var modelName: String
        public var audioDuration: Double
        public var processingTime: Double
        public var realTimeFactor: Double { audioDuration > 0 ? processingTime / audioDuration : 0 }

        public var truthCount: Int
        public var detectedCount: Int
        public var matched: Int
        /// Latencies (in seconds) for each matched note: when reported minus when actually played.
        public var latencies: [Double]
        public var missed: [(pitch: Int, time: Double)]
        public var extra: [(pitch: Int, time: Double)]

        // Score-Tracking Specific Metrics
        public var cleanTruthCount: Int
        public var cleanMatchedCount: Int
        public var cleanAcceptanceRate: Double {
            cleanTruthCount == 0 ? 1.0 : Double(cleanMatchedCount) / Double(cleanTruthCount)
        }

        public var mistakeCount: Int
        public var mistakeCaughtCount: Int
        public var mistakeDiscriminationRate: Double {
            mistakeCount == 0 ? 1.0 : Double(mistakeCaughtCount) / Double(mistakeCount)
        }

        public var neighborLeakageCount: Int
        public var neighborLeakageRate: Double {
            mistakeCount == 0 ? 0.0 : Double(neighborLeakageCount) / Double(mistakeCount)
        }

        public var ghostNotesPerMinute: Double

        // Categorical breakdowns
        public var registerBreakdowns: [Breakdown]
        public var dynamicBreakdowns: [Breakdown]

        public var precision: Double { detectedCount == 0 ? 1 : Double(matched) / Double(detectedCount) }
        public var recall: Double { truthCount == 0 ? 1 : Double(matched) / Double(truthCount) }
        public var f1: Double { precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall) }

        public func latency(percentile p: Double) -> Double {
            guard !latencies.isEmpty else { return 0 }
            let s = latencies.sorted()
            return s[min(s.count - 1, Int(Double(s.count - 1) * p))]
        }

        public init(
            modelName: String = "PianoNoteDetector",
            audioDuration: Double = 0,
            processingTime: Double = 0,
            truthCount: Int,
            detectedCount: Int,
            matched: Int,
            latencies: [Double],
            missed: [(pitch: Int, time: Double)],
            extra: [(pitch: Int, time: Double)],
            cleanTruthCount: Int = 0,
            cleanMatchedCount: Int = 0,
            mistakeCount: Int = 0,
            mistakeCaughtCount: Int = 0,
            neighborLeakageCount: Int = 0,
            ghostNotesPerMinute: Double = 0,
            registerBreakdowns: [Breakdown] = [],
            dynamicBreakdowns: [Breakdown] = []
        ) {
            self.modelName = modelName
            self.audioDuration = audioDuration
            self.processingTime = processingTime
            self.truthCount = truthCount
            self.detectedCount = detectedCount
            self.matched = matched
            self.latencies = latencies
            self.missed = missed
            self.extra = extra
            self.cleanTruthCount = cleanTruthCount
            self.cleanMatchedCount = cleanMatchedCount
            self.mistakeCount = mistakeCount
            self.mistakeCaughtCount = mistakeCaughtCount
            self.neighborLeakageCount = neighborLeakageCount
            self.ghostNotesPerMinute = ghostNotesPerMinute
            self.registerBreakdowns = registerBreakdowns
            self.dynamicBreakdowns = dynamicBreakdowns
        }
    }

    /// Automatically estimates the time offset (in seconds) between the audio recording and the MIDI ground truth.
    public static func estimateOffset(audio: [Float], sampleRate: Double, truth: [NoteEvent]) -> Double {
        guard let firstNote = truth.min(by: { $0.onset < $1.onset }) else { return 0 }

        // Find the first significant audio energy onset (RMS above 0.015)
        let window = max(128, Int(0.05 * sampleRate))
        var firstAudioOnset: Double? = nil

        var i = 0
        while i + window <= audio.count {
            var sum: Float = 0
            for j in 0..<window {
                let s = audio[i + j]
                sum += s * s
            }
            let rms = (sum / Float(window)).squareRoot()
            if rms > 0.015 {
                firstAudioOnset = Double(i) / sampleRate
                break
            }
            i += window / 2
        }

        guard let audioTime = firstAudioOnset else { return 0 }
        // Offset = audio onset time - MIDI onset time (so MIDI_onset + offset ≈ audio_onset)
        return audioTime - firstNote.onset
    }

    /// Evaluates any `AudioTranscriber` against audio and ground truth.
    public static func evaluate(
        transcriber: AudioTranscriber,
        audio: [Float],
        sampleRate: Double,
        truth: [NoteEvent],
        guide: [ChordEvent]?,
        tolerance: Double = 0.12,
        autoAlign: Bool = false
    ) -> Result {
        transcriber.reset()

        let offset = autoAlign ? estimateOffset(audio: audio, sampleRate: sampleRate, truth: truth) : 0
        let shiftedTruth = truth.map { n -> NoteEvent in
            var m = n
            m.onset += offset
            m.offset += offset
            return m
        }
        let shiftedGuide = guide?.map { c -> ChordEvent in
            let shiftedNotes = c.notes.map { n -> NoteEvent in
                var m = n
                m.onset += offset
                m.offset += offset
                return m
            }
            return ChordEvent(notes: shiftedNotes)
        }

        let audioDuration = Double(audio.count) / sampleRate
        let block = 256
        var position = 0
        var guideIndex = 0
        var detected: [DetectedNote] = []

        let startTime = DispatchTime.now()

        while position < audio.count {
            let now = Double(position) / sampleRate
            if let shiftedGuide {
                while guideIndex < shiftedGuide.count && shiftedGuide[guideIndex].onset < now - 0.15 {
                    guideIndex += 1
                }
                transcriber.expected = guideIndex < shiftedGuide.count ? shiftedGuide[guideIndex].pitches : []
            }
            let end = min(audio.count, position + block)
            let chunk = Array(audio[position..<end])
            detected += transcriber.process(chunk).filter { $0.kind == .on }
            position = end
        }

        let endTime = DispatchTime.now()
        let processingTime = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000.0

        // Match detected notes against ground truth
        var used = [Bool](repeating: false, count: detected.count)
        var latencies: [Double] = []
        var missed: [(Int, Double)] = []
        var matchedTruthIndices = Set<Int>()

        let sortedTruth = shiftedTruth.enumerated().sorted(by: { $0.element.onset < $1.element.onset })

        for (truthIndex, note) in sortedTruth {
            let match = detected.indices.first { i in
                !used[i] && detected[i].pitch == note.pitch
                    && detected[i].reportedAt >= note.onset - 0.03 && detected[i].reportedAt <= note.onset + tolerance
            }
            if let i = match {
                used[i] = true
                matchedTruthIndices.insert(truthIndex)
                latencies.append(detected[i].reportedAt - note.onset)
            } else {
                missed.append((note.pitch, note.onset))
            }
        }

        let extra = detected.indices.filter { !used[$0] }.map { (detected[$0].pitch, detected[$0].time) }

        // Analyze score-tracking specific accuracy
        var cleanTruth = 0
        var cleanMatched = 0
        var mistakes = 0
        var mistakesCaught = 0
        var neighborLeakage = 0

        if let shiftedGuide {
            for (idx, note) in shiftedTruth.enumerated() {
                // Find if the guide expected this exact pitch near this time
                let expectedChord = shiftedGuide.first(where: { abs($0.onset - note.onset) < 0.25 })
                let isClean = expectedChord?.pitches.contains(note.pitch) ?? true

                if isClean {
                    cleanTruth += 1
                    if matchedTruthIndices.contains(idx) { cleanMatched += 1 }
                } else {
                    mistakes += 1
                    // Did the detector correctly report the wrong note?
                    if matchedTruthIndices.contains(idx) {
                        mistakesCaught += 1
                    } else if let expPitches = expectedChord?.pitches {
                        // Check if the detector falsely reported the expected pitch instead!
                        let leaked = detected.contains { d in
                            expPitches.contains(d.pitch) && abs(d.time - note.onset) < tolerance
                        }
                        if leaked { neighborLeakage += 1 }
                    }
                }
            }
        } else {
            cleanTruth = truth.count
            cleanMatched = matchedTruthIndices.count
        }

        // Register breakdowns
        let bassTruth = sortedTruth.filter { $0.element.pitch < 48 }
        let midTruth = sortedTruth.filter { (48...71).contains($0.element.pitch) }
        let trebleTruth = sortedTruth.filter { $0.element.pitch > 71 }

        func makeBreakdown(name: String, notes: [(offset: Int, element: NoteEvent)]) -> Breakdown {
            let matchedInGroup = notes.filter { matchedTruthIndices.contains($0.offset) }.count
            let detectedInGroup = detected.filter { d in
                switch name {
                case "Bass (A0–B2)": return d.pitch < 48
                case "Mid (C3–B4)": return (48...71).contains(d.pitch)
                default: return d.pitch > 71
                }
            }.count
            return Breakdown(
                name: name,
                truthCount: notes.count,
                detectedCount: detectedInGroup,
                matched: matchedInGroup,
                medianLatencyMs: 0
            )
        }

        let registerBreakdowns: [Breakdown] = [
            makeBreakdown(name: "Bass (A0–B2)", notes: bassTruth),
            makeBreakdown(name: "Mid (C3–B4)", notes: midTruth),
            makeBreakdown(name: "Treble (C5–C8)", notes: trebleTruth)
        ]

        let ghostNotesPerMin = audioDuration > 0 ? Double(extra.count) / (audioDuration / 60.0) : 0

        return Result(
            modelName: transcriber.name,
            audioDuration: audioDuration,
            processingTime: processingTime,
            truthCount: truth.count,
            detectedCount: detected.count,
            matched: latencies.count,
            latencies: latencies,
            missed: missed,
            extra: extra,
            cleanTruthCount: cleanTruth,
            cleanMatchedCount: cleanMatched,
            mistakeCount: mistakes,
            mistakeCaughtCount: mistakesCaught,
            neighborLeakageCount: neighborLeakage,
            ghostNotesPerMinute: ghostNotesPerMin,
            registerBreakdowns: registerBreakdowns
        )
    }

    /// Backward compatible runner that wraps `ScoreInformedTranscriber`.
    public static func run(
        audio: [Float],
        sampleRate: Double,
        truth: [NoteEvent],
        guide: [ChordEvent]?,
        settings: PianoNoteDetector.Settings = .init(),
        tolerance: Double = 0.12
    ) -> Result {
        let transcriber = ScoreInformedTranscriber(sampleRate: sampleRate, settings: settings)
        return evaluate(transcriber: transcriber, audio: audio, sampleRate: sampleRate, truth: truth, guide: guide, tolerance: tolerance)
    }
}
