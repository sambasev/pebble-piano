import Foundation

/// A waveform summarised for drawing: the lowest and highest sample in each bucket of
/// `samplesPerBucket` mono samples. Built in one pass while the audio is read, then drawn at
/// any zoom by merging buckets into pixel columns.
public struct WaveformPeaks: Equatable, Sendable {
    public let sampleRate: Double
    public let samplesPerBucket: Int
    public private(set) var mins: [Float] = []
    public private(set) var maxs: [Float] = []

    public init(sampleRate: Double, samplesPerBucket: Int) {
        self.sampleRate = max(1, sampleRate)
        self.samplesPerBucket = max(1, samplesPerBucket)
    }

    public var bucketCount: Int { mins.count }
    public var secondsPerBucket: Double { Double(samplesPerBucket) / sampleRate }
    public var duration: Double { Double(bucketCount) * secondsPerBucket }

    mutating func appendBucket(min lo: Float, max hi: Float) {
        mins.append(lo)
        maxs.append(hi)
    }

    /// (min, max) for `columns` equal slices of the time range `start..<end` (seconds).
    /// Columns outside the audio are (0, 0).
    public func columns(from start: Double, to end: Double, count columns: Int) -> [(min: Float, max: Float)] {
        guard columns > 0, end > start, bucketCount > 0 else { return [] }
        var out = [(min: Float, max: Float)](repeating: (0, 0), count: columns)
        let bucketsPerSecond = 1 / secondsPerBucket
        let span = (end - start) / Double(columns)
        for c in 0..<columns {
            let t0 = start + Double(c) * span
            let b0 = Int((t0 * bucketsPerSecond).rounded(.down))
            let b1 = max(b0 + 1, Int(((t0 + span) * bucketsPerSecond).rounded(.up)))
            let lo = max(0, b0), hi = min(bucketCount, b1)
            guard lo < hi else { continue }
            var mn: Float = 0, mx: Float = 0
            for b in lo..<hi {
                mn = Swift.min(mn, mins[b])
                mx = Swift.max(mx, maxs[b])
            }
            out[c] = (mn, mx)
        }
        return out
    }

    /// Largest absolute sample, for scaling the drawing.
    public var peak: Float {
        var p: Float = 0
        for i in 0..<bucketCount { p = Swift.max(p, Swift.max(-mins[i], maxs[i])) }
        return p
    }
}

/// Builds `WaveformPeaks` from mono samples fed in any block sizes.
public struct WaveformBuilder {
    public private(set) var peaks: WaveformPeaks
    private var filled = 0
    private var lo: Float = 0
    private var hi: Float = 0

    /// - Parameter bucketsPerSecond: resolution kept (400 = 2.5 ms per bucket).
    public init(sampleRate: Double, bucketsPerSecond: Double = 400) {
        let perBucket = max(1, Int((sampleRate / max(1, bucketsPerSecond)).rounded()))
        peaks = WaveformPeaks(sampleRate: sampleRate, samplesPerBucket: perBucket)
    }

    public mutating func append(_ samples: UnsafeBufferPointer<Float>) {
        for s in samples {
            if filled == 0 { lo = s; hi = s } else { lo = min(lo, s); hi = max(hi, s) }
            filled += 1
            if filled == peaks.samplesPerBucket {
                peaks.appendBucket(min: lo, max: hi)
                filled = 0
            }
        }
    }

    public mutating func append(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { append($0) }
    }

    /// The summary, including a final partial bucket.
    public func finish() -> WaveformPeaks {
        var result = peaks
        if filled > 0 { result.appendBucket(min: lo, max: hi) }
        return result
    }
}

/// Tap along to find a tempo: the median of recent intervals, reset after a long pause.
public struct TapTempo: Sendable {
    public private(set) var taps: [Double] = []
    public var resetAfter: Double = 2.0
    public var keep: Int = 8

    public init() {}

    /// Records a tap at `time` (seconds, any clock). Returns the tempo once there are two taps.
    @discardableResult
    public mutating func tap(at time: Double) -> Double? {
        if let last = taps.last, time - last > resetAfter || time <= last { taps = [] }
        taps.append(time)
        if taps.count > keep { taps.removeFirst(taps.count - keep) }
        return bpm
    }

    /// Taps per minute.
    public var bpm: Double? {
        guard taps.count >= 2 else { return nil }
        let intervals = zip(taps.dropFirst(), taps).map { $0 - $1 }.sorted()
        let mid = intervals.count / 2
        let median = intervals.count % 2 == 1 ? intervals[mid] : (intervals[mid - 1] + intervals[mid]) / 2
        return median > 0 ? 60 / median : nil
    }

    public mutating func reset() { taps = [] }
}
