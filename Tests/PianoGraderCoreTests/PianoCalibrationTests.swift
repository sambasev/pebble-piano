import XCTest
@testable import PianoGraderCore

final class PianoCalibrationTests: XCTestCase {
    private let rate = 48000.0

    /// Quiet, then decaying inharmonic tones at the given times, slightly out of tune.
    private func render(_ notes: [(pitch: Int, at: Double)], cents: Double, b: Double, length: Double) -> [Float] {
        var x = [Float](repeating: 0, count: Int(length * rate))
        var seed: UInt64 = 7
        for i in x.indices {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            x[i] = (Float(seed >> 40) / Float(1 << 24) - 0.5) * 0.0005
        }
        for (pitch, at) in notes {
            let f0 = 440 * pow(2, (Double(pitch) - 69 + cents / 100) / 12)
            let start = Int(at * rate)
            for h in 1...12 {
                let f = Double(h) * f0 * (1 + b * Double(h * h)).squareRoot()
                guard f < 8000 else { break }
                let a = 0.1 * pow(Double(h), -1.2)
                for i in start..<min(x.count, start + Int(1.6 * rate)) {
                    let t = Double(i - start) / rate
                    x[i] += Float(a * exp(-t * (1.5 + 0.3 * Double(h))) * sin(2 * .pi * f * t))
                }
            }
        }
        return x
    }

    func testMeasuresTuningAndInharmonicity() throws {
        let audio = render([(60, 1.0), (62, 3.0), (64, 5.0)], cents: -12, b: 0.0004, length: 7)
        let profile = try PianoCalibration.analyse(audio, sampleRate: rate).get()
        XCTAssertEqual(profile.anchors.map(\.pitch), [60, 62, 64])
        XCTAssertEqual(profile.tuningCents, -12, accuracy: 2)
        for a in profile.anchors {
            XCTAssertEqual(a.inharmonicity, 0.0004, accuracy: 0.00015, "B for \(a.pitch)")
            XCTAssertEqual(a.partialLevels.first ?? -99, 0, accuracy: 1, "fundamental strongest")
        }
        // The detector builds templates from it and still hears the notes.
        var settings = PianoNoteDetector.Settings()
        settings.profile = profile
        let detector = PianoNoteDetector(sampleRate: rate, settings: settings)
        detector.expected = [60]
        var heard: [Int] = []
        var i = 0
        while i < audio.count {
            let end = min(audio.count, i + 256)
            for e in detector.process(Array(audio[i..<end])) where e.kind == .on { heard.append(e.pitch) }
            i = end
        }
        XCTAssertEqual(heard.first, 60)
    }

    func testRejectsTheWrongKey() {
        let audio = render([(62, 1.0), (62, 3.0), (64, 5.0)], cents: 0, b: 0.0004, length: 7)
        guard case .failure(let problem) = PianoCalibration.analyse(audio, sampleRate: rate) else {
            return XCTFail("a D played for middle C should be rejected")
        }
        XCTAssertEqual(problem, .wrongNote(wanted: 60, heard: 62))
    }

    func testNeedsAllTheNotes() {
        let audio = render([(60, 1.0)], cents: 0, b: 0.0004, length: 4)
        guard case .failure(.tooFewNotes) = PianoCalibration.analyse(audio, sampleRate: rate) else {
            return XCTFail("one note isn't a calibration")
        }
    }

    func testProfileRoundTripsAsJSON() throws {
        let profile = PianoProfile(anchors: [.init(pitch: 60, cents: -3, inharmonicity: 0.0003, partialLevels: [0, -8, -15])],
                                   noiseLevel: 0.001, created: Date(timeIntervalSince1970: 0))
        let decoded = try JSONDecoder().decode(PianoProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(profile.inharmonicity(for: 30), 0.0003, accuracy: 1e-9)
        XCTAssertEqual(profile.partialAmplitudes(for: 90, count: 5)?.count, 5)
    }
}
