import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// A note heard in microphone audio.
public struct DetectedNote: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case on, off }
    public var kind: Kind
    public var pitch: Int
    /// When the note started (on) or was released (off), in seconds of audio processed.
    public var time: Double
    /// When the detector reported it, in seconds of audio processed (time + latency).
    public var reportedAt: Double
    /// 0–1: how the note's rise compares with the strongest key of the same strike (on events
    /// only). Relative: the strongest key of every strike is 1, even a stray one.
    public var confidence: Double
    /// How far the note rose above the room's background noise (on events only; the detector
    /// reports nothing under `minimumRise`). Absolute, unlike `confidence`.
    public var strength: Double
    /// Which strike the note came from: notes of one strike share it (on events only).
    public var strike: Int

    public init(kind: Kind, pitch: Int, time: Double, reportedAt: Double, confidence: Double = 1,
                strength: Double = .infinity, strike: Int = 0) {
        self.kind = kind
        self.pitch = pitch
        self.time = time
        self.reportedAt = reportedAt
        self.confidence = confidence
        self.strength = strength
        self.strike = strike
    }
}

/// Hears piano notes in microphone audio by score-informed non-negative matrix factorisation.
///
/// 1. **Constant-Q front end.** Every hop (8 ms) the newest audio is analysed by a bank of
///    windowed complex sinusoids spaced a third of a semitone apart from A0 to about 7 kHz. High
///    bins use short windows (fast response); low bins use windows up to `maxWindow`.
/// 2. **Harmonic dictionary.** Each of the 88 keys has a template: its partials (stretched by
///    inharmonicity, rolling off with harmonic number, with a small mic's weak bass) passed
///    through the same front end. A flat column absorbs clicks and hiss, and a running per-bin
///    noise floor is modelled as fixed background.
/// 3. **NMF.** The spectrum V is explained as W·H + noise with a few multiplicative (KL) updates,
///    warm-started from the previous hop. Each key's activation has an L1 penalty: small for the
///    chord the score expects, larger for neighbours and octaves, largest for anything else.
/// 4. **Onset gating.** Keys are only reported at a hammer strike: a jump in high-frequency
///    spectral flux (and in loudness, above the room's measured background). `evaluationDelay`
///    after the strike, keys whose activation rose enough are reported. Sympathetic resonance
///    and ringing notes don't strike, so they can't re-trigger.
/// 5. **Releases.** A sounding key is reported off when its activation fades well below its peak.
public final class PianoNoteDetector {
    public struct Settings: Sendable {
        /// Time between analyses.
        public var hop: Double = 0.008
        /// Longest constant-Q window (the bass bins); shorter windows respond faster.
        public var maxWindow: Double = 0.085
        public var binsPerSemitone: Double = 3
        public var maxFrequency: Double = 7000
        public var lowestPitch = 21
        public var highestPitch = 108
        /// Piano tuning relative to A440, in cents.
        public var tuningCents: Double = 0
        public var inharmonicity: Double = 0.0004
        /// Partial h has amplitude h^-rolloff.
        public var partialRolloff: Double = 0.8
        /// Below this frequency a small microphone loses level (12 dB/octave).
        public var micLowCut: Double = 150
        /// Multiplicative NMF updates per hop.
        public var iterations = 10
        /// L1 penalties on activations, by how likely the key is.
        public var expectedPenalty: Double = 0.0
        public var neighbourPenalty: Double = 0.1
        /// Octave, twelfth and double-octave relatives of the expected notes: their templates
        /// overlap the expected notes' partials, so they need the strongest evidence.
        public var relativePenalty: Double = 0.5
        public var otherPenalty: Double = 0.3
        public var freePlayPenalty: Double = 0.05
        /// A struck key must rise by this share of the strongest rise at the strike.
        public var expectedThreshold: Double = 0.1
        public var neighbourThreshold: Double = 0.35
        public var relativeThreshold: Double = 0.5
        /// An expected key is only reported if it rose at least this share of a stronger,
        /// unexpected key a semitone or two away: neighbouring keys' templates overlap, so a
        /// wrong key (G#4 for G4) also lifts the expected one, and that spill mustn't pass.
        public var neighbourDominance: Double = 0.8
        /// A strike whose new energy is mostly broadband (the flat noise template rose more
        /// than this multiple of all the keys together) is a thump, voice or click, not a key.
        /// Set high: hammer attacks are broadband too, and on the benchmark 99.5% of real
        /// strikes stay under 4.
        public var noiseVeto: Double = 6
        public var otherThreshold: Double = 0.5
        public var freePlayThreshold: Double = 0.35
        /// …and by this multiple of the background noise's total level.
        public var minimumRise: Double = 0.5
        /// How long after a strike to decide which keys it was.
        public var evaluationDelay: Double = 0.05
        /// Lowest frequency counted in the onset flux (hammer strikes are bright).
        public var fluxLowFrequency: Double = 800
        /// Onset threshold: flux must exceed the recent median by this many times its spread.
        public var onsetSensitivity: Double = 3
        public var minimumFlux: Double = 0.5
        /// Quietest level (RMS) that can start a note, about -55 dBFS.
        public var minimumLevel: Float = 0.0018
        /// Measure the room for this long after starting, then require strikes to be
        /// `noiseGateRatio` times louder than its median level.
        public var noiseCalibration: Double = 0.75
        public var noiseGateRatio: Float = 4
        /// A strike lifts the level by this factor within a few hops.
        public var levelRise: Float = 1.25
        /// A key is off once its activation falls below this share of its peak.
        public var fadeRatio: Double = 0.1
        /// A calibrated piano: templates are built from its measured tuning, inharmonicity and
        /// partial levels instead of the generic model above.
        public var profile: PianoProfile?
        /// Shortest time between strikes (a re-strike of the same key is slower than this).
        public var minimumStrikeGap: Double = 0.09
        /// Keys below this need half the strongest rise unless expected: thumps and room
        /// rumble otherwise land on the bottom keys.
        public var bassGuardPitch = 36
        public var bassGuardThreshold: Double = 0.9

        public init() {}
    }

    public let sampleRate: Double
    public let settings: Settings
    /// The chord the player should strike next. Empty means listen without expectations.
    public var expected: Set<Int> = [] { didSet { updatePenalties() } }
    /// Recent input level (RMS of the last hop), for a level meter.
    public private(set) var level: Float = 0
    /// The quietest level that can start a note, after measuring the room.
    public private(set) var gateLevel: Float = 0
    /// A noise gate set from calibration (or "Measure silence"): used from the first sample
    /// instead of measuring the room for `noiseCalibration` seconds after starting.
    /// nil: measure the room at the start, as before.
    public var fixedGate: Float? {
        didSet { if let fixedGate { gateLevel = fixedGate } }
    }
    /// Keys the detector currently thinks are sounding.
    public var sounding: Set<Int> { Set(active.keys) }
    /// Delay from a key strike to its report, not counting audio buffering.
    public var analysisLatency: Double { settings.evaluationDelay + Double(hopLength) / sampleRate }

    // Front end
    private let hopLength: Int
    private let maxLength: Int
    private var buffer: [Float]
    private var pendingSamples = 0
    private var samplesSeen = 0
    private var frameIndex = 0
    private let binFrequencies: [Double]
    private let kernelLengths: [Int]
    private let cosKernels: [[Float]]
    private let sinKernels: [[Float]]
    private let fluxStart: Int
    private var spectrum: [Float]
    private var noiseFloor: [Float] = []
    private var previousLog: [Float] = []

    // Dictionary (bins × columns, column-major): keys then one flat column.
    private let pitches: [Int]
    private let columns: Int
    private let dictionary: [Float]
    private var activations: [Float]
    private var penalties: [Float]
    private var history: [[Float]] = []

    // Onsets and notes
    private var fluxHistory: [Double] = []
    private var lastFlux = 0.0
    private var fluxEdge: (frame: Int, before: [Float])?
    private var lastOnsetFrame = -100
    private var pendingOnset: (frame: Int, before: [Float])?
    private var active: [Int: (peak: Float, since: Int)] = [:]
    private var backgroundLevel: Float = 0
    private var recentLevels: [Float] = []
    private var calibrationLevels: [Float] = []

    public init(sampleRate: Double, settings: Settings = Settings()) {
        self.sampleRate = sampleRate
        self.settings = settings
        hopLength = max(32, Int(settings.hop * sampleRate))
        maxLength = max(256, Int(settings.maxWindow * sampleRate))
        buffer = [Float](repeating: 0, count: maxLength)

        // Bin centres: a third of a semitone apart, but never closer than half the bass
        // window's resolution (finer spacing there would only repeat the same information).
        let lowest = 440 * pow(2, (Double(settings.lowestPitch) - 69 - 0.5) / 12)
        let ratio = pow(2, 1 / (12 * settings.binsPerSemitone))
        let q = 1 / (ratio - 1)
        let minSpacing = sampleRate / Double(maxLength) * 0.5
        var freqs: [Double] = []
        var f = lowest
        while f <= min(settings.maxFrequency, sampleRate * 0.45) {
            freqs.append(f)
            f = max(f * ratio, f + minSpacing)
        }
        binFrequencies = freqs
        var lengths: [Int] = [], cosK: [[Float]] = [], sinK: [[Float]] = []
        for f in freqs {
            let n = min(maxLength, max(64, Int(q * sampleRate / f)))
            var c = [Float](repeating: 0, count: n), s = [Float](repeating: 0, count: n)
            var norm = 0.0
            for i in 0..<n {
                let w = 0.5 - 0.5 * cos(2 * Double.pi * (Double(i) + 0.5) / Double(n))
                norm += w
                let phase = 2 * Double.pi * f * Double(i) / sampleRate
                c[i] = Float(w * cos(phase))
                s[i] = Float(w * sin(phase))
            }
            let scale = Float(2 / norm)
            for i in 0..<n { c[i] *= scale; s[i] *= scale }
            lengths.append(n); cosK.append(c); sinK.append(s)
        }
        kernelLengths = lengths
        cosKernels = cosK
        sinKernels = sinK
        fluxStart = freqs.firstIndex { $0 >= settings.fluxLowFrequency } ?? 0
        spectrum = [Float](repeating: 0, count: freqs.count)

        // Templates: each key's partials through the same front end.
        pitches = Array(settings.lowestPitch...settings.highestPitch)
        columns = pitches.count + 1
        let bins = freqs.count
        var dict = [Float](repeating: 0, count: bins * columns)
        let synthLength = maxLength
        for (j, p) in pitches.enumerated() {
            let profile = settings.profile
            let cents = profile?.cents(for: p) ?? settings.tuningCents
            let f0 = 440 * pow(2, (Double(p) - 69 + cents / 100) / 12)
            let inharmonicity = profile?.inharmonicity(for: p) ?? settings.inharmonicity
            let measured = profile?.partialAmplitudes(for: p, count: 30)
            var tone = [Float](repeating: 0, count: synthLength)
            var h = 1
            while h <= 30 {
                let fh = Double(h) * f0 * (1 + inharmonicity * Double(h * h)).squareRoot()
                if fh > settings.maxFrequency * 1.05 || fh > sampleRate * 0.45 { break }
                var a = pow(Double(h), -settings.partialRolloff)
                if fh < settings.micLowCut { a *= pow(fh / settings.micLowCut, 2) }
                if let measured { a = measured[h - 1] }
                let phase0 = Double(h) * 1.7
                for i in 0..<synthLength {
                    tone[i] += Float(a * sin(2 * Double.pi * fh * Double(i) / sampleRate + phase0))
                }
                h += 1
            }
            let column = PianoNoteDetector.analyse(tone, lengths: lengths, cos: cosK, sin: sinK)
            let sum = column.reduce(0, +)
            for k in 0..<bins { dict[j * bins + k] = sum > 0 ? column[k] / sum : 0 }
        }
        for k in 0..<bins { dict[pitches.count * bins + k] = 1 / Float(bins) }
        dictionary = dict
        activations = [Float](repeating: 1e-4, count: columns)
        penalties = [Float](repeating: 0, count: columns)
        updatePenalties()
    }

    /// Feeds audio (mono, at `sampleRate`) and returns notes that started or stopped.
    public func process(_ samples: [Float]) -> [DetectedNote] {
        var events: [DetectedNote] = []
        var index = 0
        while index < samples.count {
            let take = min(samples.count - index, hopLength - pendingSamples)
            buffer.removeFirst(take)
            buffer.append(contentsOf: samples[index..<(index + take)])
            index += take
            pendingSamples += take
            samplesSeen += take
            if pendingSamples == hopLength {
                pendingSamples = 0
                events += analyseHop()
            }
        }
        return events
    }

    /// Forgets the sound so far (not the room measurement).
    public func reset() {
        for i in buffer.indices { buffer[i] = 0 }
        history = []
        fluxHistory = []
        previousLog = []
        pendingOnset = nil
        active = [:]
        lastFlux = 0
        fluxEdge = nil
        noiseFloor = []
        backgroundLevel = 0
        recentLevels = []
        for j in activations.indices { activations[j] = 1e-4 }
    }

    // MARK: Analysis

    private static func analyse(_ samples: [Float], lengths: [Int], cos: [[Float]], sin: [[Float]]) -> [Float] {
        var out = [Float](repeating: 0, count: lengths.count)
        samples.withUnsafeBufferPointer { x in
            let end = x.count
            for k in 0..<lengths.count {
                let n = lengths[k]
                let start = x.baseAddress! + (end - n)
                let re = dot(start, cos[k], n)
                let im = dot(start, sin[k], n)
                out[k] = (re * re + im * im).squareRoot()
            }
        }
        return out
    }

    private static func dot(_ a: UnsafePointer<Float>, _ b: [Float], _ n: Int) -> Float {
        #if canImport(Accelerate)
        var r: Float = 0
        b.withUnsafeBufferPointer { vDSP_dotpr(a, 1, $0.baseAddress!, 1, &r, vDSP_Length(n)) }
        return r
        #else
        return b.withUnsafeBufferPointer { bp -> Float in
            var s0: Float = 0, s1: Float = 0, s2: Float = 0, s3: Float = 0
            var i = 0
            while i + 4 <= n {
                s0 += a[i] * bp[i]; s1 += a[i + 1] * bp[i + 1]
                s2 += a[i + 2] * bp[i + 2]; s3 += a[i + 3] * bp[i + 3]
                i += 4
            }
            while i < n { s0 += a[i] * bp[i]; i += 1 }
            return s0 + s1 + s2 + s3
        }
        #endif
    }

    private func analyseHop() -> [DetectedNote] {
        frameIndex += 1
        let now = Double(samplesSeen) / sampleRate
        let hopSeconds = Double(hopLength) / sampleRate

        // Loudness and the room's background.
        var sum: Float = 0
        for i in (maxLength - hopLength)..<maxLength { sum += buffer[i] * buffer[i] }
        level = (sum / Float(hopLength)).squareRoot()
        if gateLevel == 0 { gateLevel = fixedGate ?? settings.minimumLevel }
        if fixedGate == nil, now <= settings.noiseCalibration {
            calibrationLevels.append(level)
            if now + hopSeconds > settings.noiseCalibration, !calibrationLevels.isEmpty {
                let median = calibrationLevels.sorted()[calibrationLevels.count / 2]
                gateLevel = max(settings.minimumLevel, settings.noiseGateRatio * median)
            }
        }
        if backgroundLevel == 0 { backgroundLevel = max(level, 1e-5) }
        backgroundLevel = max(1e-5, level < backgroundLevel ? backgroundLevel * 0.9 + level * 0.1 : backgroundLevel * 1.0005)
        recentLevels.append(level)
        if recentLevels.count > 4 { recentLevels.removeFirst() }
        let before = recentLevels.count >= 4 ? recentLevels[0] : 0
        let loudEnough = level >= gateLevel && level >= settings.noiseGateRatio * backgroundLevel
            && (recentLevels.count < 4 || level >= settings.levelRise * before)

        // Constant-Q spectrum and per-bin noise floor.
        spectrum = PianoNoteDetector.analyse(buffer, lengths: kernelLengths, cos: cosKernels, sin: sinKernels)
        let bins = spectrum.count
        if noiseFloor.count != bins { noiseFloor = spectrum.map { max($0, 1e-7) } }
        for k in 0..<bins {
            noiseFloor[k] = max(1e-7, noiseFloor[k] * (spectrum[k] > noiseFloor[k] ? 1.01 : 0.95))
        }

        // High-frequency flux on energy above the noise floor.
        var logSpectrum = [Float](repeating: 0, count: bins)
        for k in 0..<bins { logSpectrum[k] = log1p(max(0, spectrum[k] - 2 * noiseFloor[k]) / (noiseFloor[k] * 4)) }
        var flux = 0.0
        if previousLog.count == bins {
            for k in fluxStart..<bins {
                let d = logSpectrum[k] - previousLog[k]
                if d > 0 { flux += Double(d) }
            }
            flux /= Double(max(1, bins - fluxStart)) / 10
        }
        previousLog = logSpectrum

        factorise()
        history.append(activations)
        if history.count > 12 { history.removeFirst() }

        var events = trackReleases(at: now)

        let threshold = onsetThreshold()
        fluxHistory.append(flux)
        if fluxHistory.count > 50 { fluxHistory.removeFirst() }
        // A strike is a rising edge of flux, confirmed by a loudness jump on the same hop or
        // within the next few (an attack late in a hop shows in the spectrum before the level).
        if flux > threshold, lastFlux <= threshold || flux > lastFlux * 1.8, history.count >= 3 {
            fluxEdge = (frameIndex, history[history.count - 3])
        }
        if pendingOnset == nil, let edge = fluxEdge, frameIndex - edge.frame <= 3, loudEnough,
           Double(edge.frame - lastOnsetFrame) * hopSeconds >= settings.minimumStrikeGap {
            pendingOnset = edge
            lastOnsetFrame = edge.frame
            fluxEdge = nil
        }
        lastFlux = flux

        if let onset = pendingOnset, Double(frameIndex - onset.frame) * hopSeconds >= settings.evaluationDelay {
            pendingOnset = nil
            let onsetTime = now - Double(frameIndex - onset.frame) * hopSeconds - hopSeconds
            events += judge(before: onset.before, onsetTime: max(0, onsetTime), now: now)
        }
        return events
    }

    /// A few multiplicative KL-NMF updates of the activations, the dictionary fixed.
    private func factorise() {
        let bins = spectrum.count
        var model = [Float](repeating: 0, count: bins)
        var ratio = [Float](repeating: 0, count: bins)
        // Keys can't regrow from exactly zero; keep a tiny seed.
        let seed: Float = 1e-6 * max(1e-6, spectrum.reduce(0, +))
        for j in 0..<columns { activations[j] = max(activations[j], seed) }
        dictionary.withUnsafeBufferPointer { w in
            for _ in 0..<settings.iterations {
                for k in 0..<bins { model[k] = noiseFloor[k] }
                for j in 0..<columns {
                    let a = activations[j]
                    let base = j * bins
                    for k in 0..<bins { model[k] += w[base + k] * a }
                }
                for k in 0..<bins { ratio[k] = spectrum[k] / max(model[k], 1e-12) }
                for j in 0..<columns {
                    let base = j * bins
                    var num: Float = 0
                    for k in 0..<bins { num += w[base + k] * ratio[k] }
                    activations[j] *= num / (1 + penalties[j])
                }
            }
        }
    }

    private func onsetThreshold() -> Double {
        guard fluxHistory.count >= 8 else { return .infinity }
        let sorted = fluxHistory.sorted()
        let median = sorted[sorted.count / 2]
        let deviations = sorted.map { abs($0 - median) }.sorted()
        let mad = deviations[deviations.count / 2]
        return max(settings.minimumFlux, median + settings.onsetSensitivity * max(mad, median * 0.25))
    }

    private enum Category { case expected, neighbour, relative, other, freePlay }

    private func category(_ pitch: Int) -> Category {
        if expected.isEmpty { return .freePlay }
        if expected.contains(pitch) { return .expected }
        // Slipping to a neighbouring key, or playing an octave low, are real mistakes to catch.
        for e in expected where abs(pitch - e) <= 2 || pitch - e == -12 { return .neighbour }
        // The octave, twelfth and double octave above share the expected notes' partials.
        for e in expected where [12, 19, 24].contains(pitch - e) { return .relative }
        return .other
    }

    private func updatePenalties() {
        for (j, p) in pitches.enumerated() {
            switch category(p) {
            case .expected: penalties[j] = Float(settings.expectedPenalty)
            case .neighbour: penalties[j] = Float(settings.neighbourPenalty)
            case .relative: penalties[j] = Float(settings.relativePenalty)
            case .other: penalties[j] = Float(settings.otherPenalty)
            case .freePlay: penalties[j] = Float(settings.freePlayPenalty)
            }
        }
        penalties[pitches.count] = 0
    }

    private func threshold(for pitch: Int) -> Double {
        switch category(pitch) {
        case .expected: return settings.expectedThreshold
        case .neighbour: return settings.neighbourThreshold
        case .relative: return settings.relativeThreshold
        case .other: return settings.otherThreshold
        case .freePlay: return settings.freePlayThreshold
        }
    }

    /// Which keys the strike was: those whose activation rose enough since just before it.
    private func judge(before: [Float], onsetTime: Double, now: Double) -> [DetectedNote] {
        var rises: [(pitch: Int, rise: Double, level: Float)] = []
        for (j, p) in pitches.enumerated() {
            let rise = Double(activations[j] - before[j])
            if rise > 0 { rises.append((p, rise, activations[j])) }
        }
        guard let strongest = rises.map(\.rise).max(), strongest > 0 else { return [] }
        let noiseRise = Double(activations[pitches.count] - before[pitches.count])
        let keyRise = rises.reduce(0) { $0 + $1.rise }
        if noiseRise > settings.noiseVeto * keyRise { return [] }
        let noiseTotal = Double(noiseFloor.reduce(0, +))
        var picked: [(pitch: Int, rise: Double, level: Float)] = []
        for r in rises.sorted(by: { $0.rise > $1.rise }) {
            var needed = threshold(for: r.pitch)
            if r.pitch < settings.bassGuardPitch && !expected.contains(r.pitch) { needed = max(needed, settings.bassGuardThreshold) }
            guard r.rise >= needed * strongest, r.rise >= settings.minimumRise * noiseTotal else { continue }
            // A twelfth or an octave above a stronger struck key is usually its partials,
            // unless the score asks for it.
            if !expected.contains(r.pitch),
               picked.contains(where: { [12, 19, 24].contains(r.pitch - $0.pitch) }) { continue }
            picked.append(r)
        }
        // Spill from a stronger wrong neighbour isn't the expected key being played.
        let candidates = picked
        picked.removeAll { r in
            expected.contains(r.pitch) && candidates.contains { o in
                !expected.contains(o.pitch) && abs(o.pitch - r.pitch) <= 2 && r.rise < settings.neighbourDominance * o.rise
            }
        }
        var events: [DetectedNote] = []
        for r in picked {
            if active[r.pitch] != nil {
                events.append(DetectedNote(kind: .off, pitch: r.pitch, time: onsetTime, reportedAt: now))
            }
            active[r.pitch] = (r.level, frameIndex)
            events.append(DetectedNote(kind: .on, pitch: r.pitch, time: onsetTime, reportedAt: now,
                                       confidence: min(1, r.rise / strongest),
                                       strength: r.rise / max(noiseTotal, 1e-12), strike: frameIndex))
        }
        return events
    }

    private func trackReleases(at now: Double) -> [DetectedNote] {
        guard !active.isEmpty else { return [] }
        var events: [DetectedNote] = []
        let floorLevel = noiseFloor.reduce(0, +) * 0.3
        for (pitch, note) in active {
            guard let j = pitches.firstIndex(of: pitch) else { continue }
            let a = activations[j]
            let peak = max(note.peak, a)
            active[pitch]?.peak = peak
            if frameIndex - note.since > 6, a < Float(settings.fadeRatio) * peak || a < floorLevel {
                active[pitch] = nil
                events.append(DetectedNote(kind: .off, pitch: pitch, time: now, reportedAt: now))
            }
        }
        return events.sorted { $0.pitch < $1.pitch }
    }
}
