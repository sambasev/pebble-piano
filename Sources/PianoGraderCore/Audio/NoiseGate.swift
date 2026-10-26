import Foundation

/// The room's background noise, measured while nobody plays, and the simple gate set from it:
/// a note can only start when the input is louder than the gate.
public struct RoomNoise: Codable, Equatable, Sendable {
    /// Typical background level (median RMS of 10 ms slices).
    public var median: Float
    /// Its loud moments (95th percentile): fans, hum, the odd click.
    public var peak: Float
    public var measured: Date

    public init(median: Float, peak: Float, measured: Date = Date()) {
        self.median = median
        self.peak = max(median, peak)
        self.measured = measured
    }

    /// Quietest level any gate uses (about −55 dBFS), so a silent mic doesn't make a hair trigger.
    public static let minimumGate: Float = 0.0018
    /// A room this loud leaves no room under a normal piano note (about −30 dBFS).
    public static let tooNoisyGate: Float = 0.0316

    /// The gate: loud moments +6 dB, typical noise +12 dB, never below `minimumGate`.
    public var gate: Float { max(Self.minimumGate, peak * 2, median * 4) }

    public var isTooNoisy: Bool { gate >= Self.tooNoisyGate }

    /// Measures a stretch of silence (mono samples).
    public static func measure(_ samples: ArraySlice<Float>, sampleRate: Double) -> RoomNoise? {
        let hop = max(1, Int(0.01 * sampleRate))
        guard samples.count >= hop * 10 else { return nil }
        var levels: [Float] = []
        var i = samples.startIndex
        while i + hop <= samples.endIndex {
            var s: Float = 0
            for j in i..<(i + hop) { s += samples[j] * samples[j] }
            levels.append((s / Float(hop)).squareRoot())
            i += hop
        }
        levels.sort()
        return RoomNoise(median: levels[levels.count / 2], peak: levels[min(levels.count - 1, levels.count * 95 / 100)])
    }

    public static func measure(_ samples: [Float], sampleRate: Double) -> RoomNoise? {
        measure(samples[...], sampleRate: sampleRate)
    }

    /// A gate moved by `offsetDB` (positive: stricter).
    public static func adjusted(_ gate: Float, offsetDB: Double) -> Float {
        max(Self.minimumGate * 0.25, gate * Float(pow(10, offsetDB / 20)))
    }

    /// Level in dBFS, for display.
    public static func dB(_ level: Float) -> Double { 20 * log10(max(Double(level), 1e-9)) }
}
