import Foundation

/// A heuristic spectral peak baseline transcriber.
/// Detects note onsets via energy rise and identifies pitches from direct FFT spectral peak picking,
/// without NMF dictionary factorization. Used as an algorithmic baseline to quantify the benefit of NMF.
public final class SpectralPeakTranscriber: AudioTranscriber {
    public let name = "Spectral Peak (DSP Baseline)"
    public let methodDescription = "Direct FFT peak picking and harmonic series matching without NMF"

    public var expected: Set<Int> = []

    private let sampleRate: Double
    private let fftSize: Int = 4096
    private let hopSize: Int
    private let fft: MagnitudeFFT
    private var window: [Float]
    private var buffer: [Float]
    private var spectrum: [Float] = []
    private var previousEnergy: Float = 0
    private var samplesProcessed: Int = 0
    private var activeNotes: Set<Int> = []
    private var lastOnsetSample: Int = -10000

    public init(sampleRate: Double, hop: Double = 0.008) {
        self.sampleRate = sampleRate
        self.hopSize = max(32, Int(hop * sampleRate))
        self.fft = MagnitudeFFT(size: fftSize)
        self.buffer = [Float](repeating: 0, count: fftSize)

        // Hann window
        var win = [Float](repeating: 0, count: fftSize)
        for i in 0..<fftSize {
            win[i] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(fftSize)))
        }
        self.window = win
    }

    public func reset() {
        buffer = [Float](repeating: 0, count: fftSize)
        previousEnergy = 0
        samplesProcessed = 0
        activeNotes.removeAll()
        lastOnsetSample = -10000
    }

    public func process(_ samples: [Float]) -> [DetectedNote] {
        var events: [DetectedNote] = []
        var index = 0

        while index < samples.count {
            let chunk = min(samples.count - index, hopSize)
            buffer.removeFirst(chunk)
            buffer.append(contentsOf: samples[index..<(index + chunk)])
            index += chunk
            samplesProcessed += chunk

            // Windowed audio for FFT
            var windowed = [Float](repeating: 0, count: fftSize)
            var currentEnergy: Float = 0
            for i in 0..<fftSize {
                let s = buffer[i] * window[i]
                windowed[i] = s
                currentEnergy += s * s
            }

            let energyDelta = currentEnergy - previousEnergy
            let currentTime = Double(samplesProcessed) / sampleRate

            // Onset trigger: jump in energy after quiet or steady state
            if energyDelta > 0.005 && currentEnergy > 0.001 && (samplesProcessed - lastOnsetSample) > Int(0.08 * sampleRate) {
                lastOnsetSample = samplesProcessed
                fft.magnitudes(of: windowed, count: fftSize / 2, into: &spectrum)

                // Search for prominent pitch candidates between MIDI 21 (A0, 27.5Hz) and 108 (C8, 4186Hz)
                var bestPitch: Int? = nil
                var bestScore: Float = 0

                let candidatePitches = expected.isEmpty ? Array(21...108) : Array(expected)

                for pitch in candidatePitches {
                    let f0 = 440.0 * pow(2.0, Double(pitch - 69) / 12.0)
                    let bin = Int((f0 * Double(fftSize) / sampleRate).rounded())
                    guard bin > 1 && bin < spectrum.count - 1 else { continue }

                    // Peak magnitude at f0
                    let mag = spectrum[bin]
                    // Bias towards expected notes if present
                    let weight: Float = expected.contains(pitch) ? 1.5 : 1.0
                    let score = mag * weight

                    if score > bestScore && mag > 0.05 {
                        bestScore = score
                        bestPitch = pitch
                    }
                }

                if let pitch = bestPitch {
                    // Turn off previous notes if playing new one
                    for old in activeNotes where old != pitch {
                        events.append(DetectedNote(kind: .off, pitch: old, time: currentTime, reportedAt: currentTime))
                    }
                    activeNotes.removeAll()

                    activeNotes.insert(pitch)
                    events.append(DetectedNote(kind: .on, pitch: pitch, time: currentTime, reportedAt: currentTime + 0.05, confidence: Double(min(1.0, bestScore))))
                }
            } else if currentEnergy < 0.0005 && !activeNotes.isEmpty {
                // Fade off
                for old in activeNotes {
                    events.append(DetectedNote(kind: .off, pitch: old, time: currentTime, reportedAt: currentTime))
                }
                activeNotes.removeAll()
            }

            previousEnergy = currentEnergy
        }

        return events
    }
}
