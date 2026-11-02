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

/// Runs the detector over a recording and scores it against the notes actually played.
public enum DetectorEvaluation {
    public struct Result: Sendable {
        public var truthCount: Int
        public var detectedCount: Int
        public var matched: Int
        /// Detection latency for each matched note: when it was reported minus when it was played.
        public var latencies: [Double]
        public var missed: [(pitch: Int, time: Double)]
        public var extra: [(pitch: Int, time: Double)]

        public var precision: Double { detectedCount == 0 ? 1 : Double(matched) / Double(detectedCount) }
        public var recall: Double { truthCount == 0 ? 1 : Double(matched) / Double(truthCount) }
        public var f1: Double { precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall) }
        public func latency(percentile p: Double) -> Double {
            guard !latencies.isEmpty else { return 0 }
            let s = latencies.sorted()
            return s[min(s.count - 1, Int(Double(s.count - 1) * p))]
        }
    }

    /// - Parameters:
    ///   - truth: the notes really played (onsets in seconds from the start of the audio).
    ///   - guide: the score the player follows: before each guide chord's time, the detector is
    ///     told to expect it, as wait mode would. nil for free play.
    ///   - tolerance: a detection matches a played note of the same pitch starting at most this
    ///     long before it (or slightly after, for early estimates).
    public static func run(audio: [Float], sampleRate: Double, truth: [NoteEvent], guide: [ChordEvent]?,
                           settings: PianoNoteDetector.Settings = .init(), tolerance: Double = 0.12) -> Result {
        let detector = PianoNoteDetector(sampleRate: sampleRate, settings: settings)
        var detected: [DetectedNote] = []
        let block = 256
        var position = 0
        var guideIndex = 0
        while position < audio.count {
            let now = Double(position) / sampleRate
            if let guide {
                // The guide moves on once its chord's time has passed (as when it was played).
                while guideIndex < guide.count && guide[guideIndex].onset < now - 0.15 { guideIndex += 1 }
                detector.expected = guideIndex < guide.count ? guide[guideIndex].pitches : []
            }
            let end = min(audio.count, position + block)
            detected += detector.process(Array(audio[position..<end])).filter { $0.kind == .on }
            position = end
        }

        var used = [Bool](repeating: false, count: detected.count)
        var latencies: [Double] = []
        var missed: [(Int, Double)] = []
        for note in truth.sorted(by: { $0.onset < $1.onset }) {
            let match = detected.indices.first { i in
                !used[i] && detected[i].pitch == note.pitch
                    && detected[i].reportedAt >= note.onset - 0.03 && detected[i].reportedAt <= note.onset + tolerance
            }
            if let i = match {
                used[i] = true
                latencies.append(detected[i].reportedAt - note.onset)
            } else {
                missed.append((note.pitch, note.onset))
            }
        }
        let extra = detected.indices.filter { !used[$0] }.map { (detected[$0].pitch, detected[$0].time) }
        return Result(truthCount: truth.count, detectedCount: detected.count, matched: latencies.count,
                      latencies: latencies, missed: missed, extra: extra)
    }
}
