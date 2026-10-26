import XCTest
@testable import PianoGraderCore

final class FFTTests: XCTestCase {
    func testSinePeakLandsOnItsBin() {
        let n = 4096, rate = 48000.0
        let fft = MagnitudeFFT(size: n)
        for frequency in [110.0, 261.63, 440.0, 1000.0, 3520.0] {
            let input = (0..<2048).map { Float(sin(2 * Double.pi * frequency * Double($0) / rate)) }
            var out: [Float] = []
            fft.magnitudes(of: input, count: n / 2, into: &out)
            let peak = out.indices.max { out[$0] < out[$1] }!
            XCTAssertEqual(Double(peak) * rate / Double(n), frequency, accuracy: rate / Double(n), "\(frequency) Hz")
            // A unit sine over 2048 samples (no window) peaks near 2048 / 2.
            XCTAssertEqual(Double(out[peak]), 1024, accuracy: 300)
        }
    }

    func testMatchesNaiveDFT() {
        let input: [Float] = (0..<64).map { Float(sin(Double($0) * 0.37) + 0.5 * cos(Double($0) * 1.9)) }
        let fft = MagnitudeFFT(size: 64)
        var out: [Float] = []
        fft.magnitudes(of: input, count: 32, into: &out)
        for k in 0..<32 {
            var re = 0.0, im = 0.0
            for (i, x) in input.enumerated() {
                re += Double(x) * cos(-2 * Double.pi * Double(k * i) / 64)
                im += Double(x) * sin(-2 * Double.pi * Double(k * i) / 64)
            }
            XCTAssertEqual(Double(out[k]), (re * re + im * im).squareRoot(), accuracy: 1e-3, "bin \(k)")
        }
    }
}

final class PianoNoteDetectorTests: XCTestCase {
    private let rate = 48000.0

    /// A struck-string tone: decaying partials (slightly sharp up high, as on a real string) over quiet noise.
    private func render(_ notes: [(pitch: Int, start: Double)], length: Double) -> [Float] {
        var out = [Float](repeating: 0, count: Int(length * rate))
        var seed: UInt64 = 42
        for i in out.indices {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            out[i] = (Float(seed >> 40) / Float(1 << 24) - 0.5) * 0.0004
        }
        for note in notes {
            let f0 = 440 * pow(2, Double(note.pitch - 69) / 12)
            let first = Int(note.start * rate)
            for h in 1...10 {
                let f = Double(h) * f0 * (1 + 0.0004 * Double(h * h)).squareRoot()
                guard f < 8000 else { break }
                let amp = 0.08 / pow(Double(h), 0.9)
                for i in first..<out.count {
                    let t = Double(i - first) / rate
                    out[i] += Float(amp * exp(-t * (1.5 + 0.4 * Double(h))) * sin(2 * Double.pi * f * t))
                }
            }
        }
        return out
    }

    private func run(_ audio: [Float], expected: Set<Int> = []) -> [DetectedNote] {
        let detector = PianoNoteDetector(sampleRate: rate)
        detector.expected = expected
        var events: [DetectedNote] = []
        var i = 0
        while i < audio.count {
            let end = min(audio.count, i + 256)
            events += detector.process(Array(audio[i..<end]))
            i = end
        }
        return events.filter { $0.kind == .on }
    }

    func testHearsTheExpectedNoteQuickly() {
        let events = run(render([(60, 0.5)], length: 1.2), expected: [60])
        XCTAssertEqual(events.map(\.pitch), [60])
        let latency = events[0].reportedAt - 0.5
        XCTAssertLessThan(latency, 0.08, "reported \(Int(latency * 1000)) ms after the strike")
        XCTAssertGreaterThan(latency, 0)
    }

    func testHearsAWrongNeighbourInsteadOfTheExpectedNote() {
        // The score wants D4; E4 is played.
        let events = run(render([(64, 0.5)], length: 1.2), expected: [62])
        XCTAssertEqual(events.map(\.pitch), [64])
    }

    func testFollowsAMelodyWithLegato() {
        let melody = [(60, 0.4), (62, 0.8), (64, 1.2), (65, 1.6), (67, 2.0)]
        let audio = render(melody, length: 2.6)
        let detector = PianoNoteDetector(sampleRate: rate)
        var heard: [Int] = []
        var i = 0
        var next = 0
        while i < audio.count {
            let now = Double(i) / rate
            while next < melody.count && melody[next].1 < now - 0.12 { next += 1 }
            detector.expected = next < melody.count ? [melody[next].0] : []
            let end = min(audio.count, i + 256)
            heard += detector.process(Array(audio[i..<end])).filter { $0.kind == .on }.map(\.pitch)
            i = end
        }
        XCTAssertEqual(heard, melody.map(\.0))
    }

    func testSilenceAndNoiseAreQuiet() {
        XCTAssertTrue(run(render([], length: 1.5)).isEmpty)
    }
}
