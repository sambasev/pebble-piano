import Foundation

/// What calibration learned about one piano, through one microphone in one room.
///
/// A few notes are enough (by default C4, D4 and E4, the first notes a beginner plays): each is measured for its exact tuning,
/// string inharmonicity and the level of each partial as the microphone hears it. The detector
/// builds all 88 key templates from these anchors, interpolating between them by pitch, so the
/// templates carry the real piano's brightness, the mic's bass loss and the room's colour.
public struct PianoProfile: Codable, Equatable, Sendable {
    public struct Anchor: Codable, Equatable, Sendable {
        /// The key that was played.
        public var pitch: Int
        /// Its measured tuning, in cents from equal temperament at A440.
        public var cents: Double
        /// Measured inharmonicity coefficient B (partial n sits at n·f0·√(1 + B·n²)).
        public var inharmonicity: Double
        /// Level of partials 1, 2, 3… in dB relative to the strongest.
        public var partialLevels: [Double]

        public init(pitch: Int, cents: Double, inharmonicity: Double, partialLevels: [Double]) {
            self.pitch = pitch
            self.cents = cents
            self.inharmonicity = inharmonicity
            self.partialLevels = partialLevels
        }
    }

    public var anchors: [Anchor]
    /// Background level (RMS) of the room while the player was quiet.
    public var noiseLevel: Float
    /// Loud moments of that background (95th percentile). Missing in older profiles.
    public var noisePeak: Float?
    public var created: Date

    public init(anchors: [Anchor], noiseLevel: Float, noisePeak: Float? = nil, created: Date = Date()) {
        self.anchors = anchors.sorted { $0.pitch < $1.pitch }
        self.noiseLevel = noiseLevel
        self.noisePeak = noisePeak
        self.created = created
    }

    /// The room as measured during calibration. Older profiles only kept the typical level,
    /// which then stands for the loud moments too (giving a gate of noise +12 dB).
    public var roomNoise: RoomNoise {
        RoomNoise(median: noiseLevel, peak: noisePeak ?? noiseLevel, measured: created)
    }

    /// Takes a new measurement of the room (from "Measure silence").
    public mutating func update(_ room: RoomNoise) {
        noiseLevel = room.median
        noisePeak = room.peak
    }

    /// The piano's tuning offset (median over the anchors), in cents.
    public var tuningCents: Double {
        let c = anchors.map(\.cents).sorted()
        return c.isEmpty ? 0 : c[c.count / 2]
    }

    /// Tuning of any key in cents, interpolated between anchors (pianos are stretch-tuned).
    public func cents(for pitch: Int) -> Double {
        interpolate(pitch) { $0.cents } ?? 0
    }

    /// Inharmonicity for any key: interpolated in log B between anchors, held beyond them.
    public func inharmonicity(for pitch: Int) -> Double {
        interpolate(pitch) { log(max($0.inharmonicity, 1e-5)) }.map(exp) ?? 0.0004
    }

    /// Partial levels (linear amplitude, strongest 1) for any key, interpolated in dB between
    /// the nearest anchors. Partials an anchor didn't measure continue its last slope.
    public func partialAmplitudes(for pitch: Int, count: Int) -> [Double]? {
        guard !anchors.isEmpty else { return nil }
        var out: [Double] = []
        for h in 1...count {
            guard let db = interpolate(pitch, { PianoProfile.level(of: $0, partial: h) }) else { return nil }
            out.append(pow(10, db / 20))
        }
        return out
    }

    private static func level(of anchor: Anchor, partial h: Int) -> Double {
        let levels = anchor.partialLevels
        if h <= levels.count { return levels[h - 1] }
        guard levels.count >= 2 else { return (levels.last ?? 0) - 6 * Double(h - levels.count) }
        // Continue the average fall of the last few partials, at least 3 dB per partial.
        let tail = Array(levels.suffix(4))
        let slope = min(-3, (tail.last! - tail.first!) / Double(max(1, tail.count - 1)))
        return max(-80, levels.last! + slope * Double(h - levels.count))
    }

    private func interpolate(_ pitch: Int, _ value: (Anchor) -> Double) -> Double? {
        guard let first = anchors.first, let last = anchors.last else { return nil }
        if pitch <= first.pitch { return value(first) }
        if pitch >= last.pitch { return value(last) }
        for (a, b) in zip(anchors, anchors.dropFirst()) where pitch >= a.pitch && pitch <= b.pitch {
            let t = Double(pitch - a.pitch) / Double(max(1, b.pitch - a.pitch))
            return value(a) * (1 - t) + value(b) * t
        }
        return value(last)
    }
}

/// Measures a piano from a short recording: a moment of quiet, then the requested notes one
/// at a time, each left to ring for about a second.
public enum PianoCalibration {
    public enum Problem: Error, Equatable, CustomStringConvertible {
        case tooFewNotes(heard: Int, wanted: Int)
        /// The note heard isn't the key asked for (it's `heard`, as near as can be told).
        case wrongNote(wanted: Int, heard: Int)
        /// The sound doesn't look like a piano string: too few partials, or it doesn't decay.
        case notAPiano(pitch: Int)
        case tooQuiet
        /// The room was too loud while it should have been quiet: no usable noise gate.
        case tooNoisy(dBFS: Double)

        public var description: String {
            switch self {
            case .tooFewNotes(let heard, let wanted): return "Heard \(heard) of the \(wanted) notes. Play each one firmly and let it ring."
            case .wrongNote(let wanted, let heard): return "Expected \(PitchName.of(wanted)) but heard \(PitchName.of(heard))."
            case .notAPiano(let pitch): return "\(PitchName.of(pitch)) didn't sound like a piano string. Try again in a quieter room."
            case .tooQuiet: return "The notes were too quiet. Move closer to the piano or play louder."
            case .tooNoisy(let db): return String(format: "The room was too noisy while it should have been quiet (%.0f dBFS). Try again in a quieter moment.", db)
            }
        }
    }

    /// The notes calibration asks for, in order: middle C, D and E, where beginners play.
    /// Keys outside them use the nearest one's measurements.
    public static let defaultNotes = [60, 62, 64]

    /// Finds the struck notes in `samples` (in order) and measures each one.
    /// - Parameter silence: where in the recording the player was asked to stay quiet
    ///   (seconds). The room's noise, and so the noise gate, is measured there. Without it,
    ///   the quietest fifth of the recording stands in.
    public static func analyse(_ samples: [Float], sampleRate: Double, notes: [Int] = defaultNotes,
                               silence: Range<Double>? = nil) -> Result<PianoProfile, Problem> {
        let hop = max(1, Int(0.005 * sampleRate))
        let frames = samples.count / hop
        guard frames > 20 else { return .failure(.tooFewNotes(heard: 0, wanted: notes.count)) }
        var levels = [Double](repeating: 0, count: frames)
        for i in 0..<frames {
            var s = 0.0
            for j in (i * hop)..<((i + 1) * hop) { s += Double(samples[j] * samples[j]) }
            levels[i] = 10 * log10(s / Double(hop) + 1e-14)
        }
        // Background: the quietest fifth of the recording, for finding the notes.
        let quiet = levels.sorted()[frames / 5]
        let noise = Float(pow(10, quiet / 20))
        // The room for the noise gate: the quiet stretch, when we know where it was.
        var room = RoomNoise(median: noise, peak: noise)
        if let silence {
            let a = max(0, min(samples.count, Int(silence.lowerBound * sampleRate)))
            let b = max(a, min(samples.count, Int(silence.upperBound * sampleRate)))
            if let measured = RoomNoise.measure(samples[a..<b], sampleRate: sampleRate) { room = measured }
        }
        if room.isTooNoisy { return .failure(.tooNoisy(dBFS: RoomNoise.dB(room.peak))) }

        // Onsets: a rise of 8 dB within 25 ms to well above the background, at least 0.4 s apart.
        var onsets: [Int] = []
        var i = 5
        while i < frames {
            if levels[i] - levels[i - 5] > 8, levels[i] > quiet + 12 {
                // Settle on the frame where the attack peaks.
                var peak = i
                while peak + 1 < frames && peak < i + 6 && levels[peak + 1] > levels[peak] { peak += 1 }
                onsets.append(i)
                i = peak + Int(0.4 * sampleRate) / hop
            } else {
                i += 1
            }
        }
        // Keep the strongest notes if there were extra thumps, in time order.
        if onsets.count > notes.count {
            let strongest = onsets.sorted { levels[min(frames - 1, $0 + 4)] > levels[min(frames - 1, $1 + 4)] }.prefix(notes.count)
            onsets = strongest.sorted()
        }
        guard onsets.count == notes.count else { return .failure(.tooFewNotes(heard: onsets.count, wanted: notes.count)) }

        var anchors: [PianoProfile.Anchor] = []
        for (onset, pitch) in zip(onsets, notes) {
            switch measure(samples, from: onset * hop, pitch: pitch, sampleRate: sampleRate, noise: noise) {
            case .success(let anchor): anchors.append(anchor)
            case .failure(let problem): return .failure(problem)
            }
        }
        return .success(PianoProfile(anchors: anchors, noiseLevel: room.median, noisePeak: room.peak))
    }

    /// Measures one note from 100 ms after its strike.
    static func measure(_ samples: [Float], from start: Int, pitch: Int, sampleRate: Double, noise: Float) -> Result<PianoProfile.Anchor, Problem> {
        let size = 16384
        let begin = start + Int(0.1 * sampleRate)
        guard begin + size <= samples.count else { return .failure(.tooFewNotes(heard: 0, wanted: 1)) }
        let spectrum = finestSpectrum(Array(samples[begin..<(begin + size)]))
        let binHz = sampleRate / Double(spectrum.count * 2)
        let median = Double(spectrum.sorted()[spectrum.count / 2])

        // Where is the note? Search ±1 semitone and its octaves for the best harmonic match,
        // so a wrong key is reported rather than measured.
        func partials(f0: Double, b: Double, count: Int) -> [(h: Int, freq: Double, amp: Double)] {
            var out: [(Int, Double, Double)] = []
            for h in 1...count {
                let centre = Double(h) * f0 * (1 + b * Double(h * h)).squareRoot()
                guard centre < sampleRate * 0.45, centre < 8000 else { break }
                let lo = max(1, Int(centre * pow(2, -0.35 / 12) / binHz))
                let hi = min(spectrum.count - 2, Int(centre * pow(2, 0.35 / 12) / binHz) + 1)
                guard lo < hi else { continue }
                var k = lo
                for j in lo...hi where spectrum[j] > spectrum[k] { k = j }
                // Parabolic interpolation for the exact peak.
                let a = Double(spectrum[k - 1]), c = Double(spectrum[k]), d = Double(spectrum[k + 1])
                let offset = (a - 2 * c + d) != 0 ? 0.5 * (a - d) / (a - 2 * c + d) : 0
                out.append((h, (Double(k) + offset) * binHz, c))
            }
            return out
        }
        func score(_ p: Double) -> Double {
            let f0 = 440 * pow(2, (p - 69) / 12)
            let found = partials(f0: f0, b: 0.0003, count: 8)
            let total = found.reduce(0) { $0 + log1p($1.amp / (median + 1e-12)) }
            // A key an octave (or more) too low still "explains" the real partials, but its own
            // fundamental and odd partials are missing: count only what it adds.
            let strongest = found.map(\.amp).max() ?? 0
            let fundamental = found.first { $0.h == 1 }?.amp ?? 0
            let present = fundamental > 0.05 * strongest && fundamental > 6 * median
            return present ? total : total * 0.3
        }
        var best = Double(pitch), bestScore = -1.0
        for step in stride(from: -14.0, through: 14.0, by: 0.25) where step.truncatingRemainder(dividingBy: 1) == 0 || abs(step) <= 1 {
            let s = score(Double(pitch) + step)
            if s > bestScore { bestScore = s; best = Double(pitch) + step }
        }
        let heard = Int(best.rounded())
        guard abs(best - Double(pitch)) <= 1 else { return .failure(.wrongNote(wanted: pitch, heard: heard)) }

        // Fit f0 and B to the partials that stand clear of the background.
        var f0 = 440 * pow(2, (best - 69) / 12)
        var b = 0.0003
        var found: [(h: Int, freq: Double, amp: Double)] = []
        for _ in 0..<3 {
            found = partials(f0: f0, b: b, count: 16)
            let clear = found.filter { $0.amp > 6 * median }
            // B needs several partials to pin down; with fewer keep a typical value.
            guard clear.count >= 4 else { break }
            // (f_h / h)² = f0² + f0²·B·h²: a straight line in h².
            let xs = clear.map { Double($0.h * $0.h) }
            let ys = clear.map { pow($0.freq / Double($0.h), 2) }
            let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
            var sxx = 0.0, sxy = 0.0
            for (x, y) in zip(xs, ys) { sxx += (x - mx) * (x - mx); sxy += (x - mx) * (y - my) }
            let slope = sxx > 0 ? sxy / sxx : 0
            let intercept = my - slope * mx
            guard intercept > 0 else { break }
            f0 = intercept.squareRoot()
            b = min(0.0015, max(0.00005, slope / intercept))
        }
        let clear = found.filter { $0.amp > 6 * median }
        guard clear.count >= 3 else { return .failure(.notAPiano(pitch: pitch)) }

        // A struck string decays; a hum or a held electronic tone doesn't.
        let early = rms(samples, from: begin, count: Int(0.1 * sampleRate))
        let late = rms(samples, from: begin + Int(0.5 * sampleRate), count: Int(0.1 * sampleRate))
        if late > early * 1.05 { return .failure(.notAPiano(pitch: pitch)) }
        if early < noise * 3 { return .failure(.tooQuiet) }

        let strongest = found.map(\.amp).max() ?? 1
        let floorDB = 20 * log10(6 * median / strongest)
        var levels = found.map { max(floorDB, 20 * log10(max($0.amp, 1e-12) / strongest)) }
        while levels.count > 3, let last = levels.last, last <= floorDB + 0.01 { levels.removeLast() }
        let cents = 1200 * log2(f0 / (440 * pow(2, (Double(pitch) - 69) / 12)))
        return .success(PianoProfile.Anchor(pitch: pitch, cents: cents, inharmonicity: b, partialLevels: levels))
    }

    private static func rms(_ x: [Float], from start: Int, count: Int) -> Float {
        let end = min(x.count, start + count)
        guard end > start else { return 0 }
        var s: Float = 0
        for i in start..<end { s += x[i] * x[i] }
        return (s / Float(end - start)).squareRoot()
    }

    /// Hann-windowed magnitude spectrum, zero-padded 4× for finer peak positions.
    private static func finestSpectrum(_ x: [Float]) -> [Float] {
        let n = x.count * 4
        var windowed = [Float](repeating: 0, count: n)
        for i in 0..<x.count {
            windowed[i] = x[i] * Float(0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(x.count - 1)))
        }
        let fft = MagnitudeFFT(size: n)
        var out = [Float](repeating: 0, count: n / 2)
        fft.magnitudes(of: windowed, count: n / 2, into: &out)
        return out
    }
}
