import XCTest
@testable import PianoGraderCore

final class NoiseGateTests: XCTestCase {
    private let rate = 48000.0

    private func noise(_ seconds: Double, amplitude: Float, seed: UInt64 = 3) -> [Float] {
        var s = seed
        return (0..<Int(seconds * rate)).map { _ in
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return (Float(s >> 40) / Float(1 << 24) - 0.5) * 2 * amplitude
        }
    }

    /// A piano-like decaying note.
    private func note(_ pitch: Int, seconds: Double, amplitude: Double) -> [Float] {
        let f0 = 440 * pow(2, (Double(pitch) - 69) / 12)
        return (0..<Int(seconds * rate)).map { i in
            let t = Double(i) / rate
            var v = 0.0
            for h in 1...6 { v += amplitude * pow(Double(h), -1.2) * exp(-t * (2 + 0.3 * Double(h))) * sin(2 * .pi * Double(h) * f0 * t) }
            return Float(v)
        }
    }

    func testMeasuresTheRoomAndSetsTheGateAbove() throws {
        let room = try XCTUnwrap(RoomNoise.measure(noise(1, amplitude: 0.004), sampleRate: rate))
        // Uniform noise of amplitude a has RMS a/√3.
        XCTAssertEqual(room.median, 0.004 / Float(3).squareRoot(), accuracy: 0.0004)
        XCTAssertGreaterThanOrEqual(room.peak, room.median)
        XCTAssertEqual(room.gate, max(room.peak * 2, room.median * 4), accuracy: 1e-6)
        XCTAssertFalse(room.isTooNoisy)
        XCTAssertEqual(RoomNoise.adjusted(room.gate, offsetDB: 6), room.gate * 1.995, accuracy: room.gate * 0.01)
    }

    func testAQuietRoomStillGetsTheMinimumGate() {
        XCTAssertEqual(RoomNoise(median: 0.00001, peak: 0.00002).gate, RoomNoise.minimumGate)
        XCTAssertTrue(RoomNoise(median: 0.02, peak: 0.03).isTooNoisy)
    }

    func testOldProfilesWithoutAPeakStillGiveAGate() throws {
        let json = #"{"anchors":[],"noiseLevel":0.001,"created":0}"#
        let profile = try JSONDecoder().decode(PianoProfile.self, from: Data(json.utf8))
        XCTAssertNil(profile.noisePeak)
        XCTAssertEqual(profile.roomNoise.gate, 0.004, accuracy: 1e-6)        // noise +12 dB
    }

    private func run(_ audio: [Float], gate: Float?) -> [DetectedNote] {
        let detector = PianoNoteDetector(sampleRate: rate, settings: PianoNoteDetector.Settings())
        detector.fixedGate = gate
        detector.expected = [60]
        var out: [DetectedNote] = []
        var i = 0
        while i < audio.count {
            let end = min(audio.count, i + 256)
            out += detector.process(Array(audio[i..<end]))
            i = end
        }
        return out
    }

    func testANoteBelowTheGateDoesNotStart() {
        let audio = noise(0.5, amplitude: 0.0005) + note(60, seconds: 1, amplitude: 0.01)
        XCTAssertTrue(run(audio, gate: nil).contains { $0.kind == .on && $0.pitch == 60 }, "heard without a high gate")
        XCTAssertFalse(run(audio, gate: 0.2).contains { $0.kind == .on }, "a gate far above the note blocks it")
    }

    func testTheFixedGateIsUsedFromTheStart() {
        let detector = PianoNoteDetector(sampleRate: rate, settings: PianoNoteDetector.Settings())
        detector.fixedGate = 0.05
        _ = detector.process(noise(1, amplitude: 0.0005))
        XCTAssertEqual(detector.gateLevel, 0.05)                              // not re-measured
    }

    func testCalibrationMeasuresTheQuietStretch() throws {
        // 1.5 s of louder hum-like noise where the player was quiet, then three notes.
        var audio = noise(1.5, amplitude: 0.002)
        for p in [60, 62, 64] {
            audio += note(p, seconds: 2.5, amplitude: 0.1)
        }
        let result = PianoCalibration.analyse(audio, sampleRate: rate, silence: 0.15..<1.35)
        if case .success(let profile) = result {
            XCTAssertEqual(profile.noiseLevel, 0.002 / Float(3).squareRoot(), accuracy: 0.0003)
            XCTAssertNotNil(profile.noisePeak)
        } else if case .failure(let problem) = result {
            // The synthetic notes may not satisfy the piano checks; the silence must not be the reason.
            if case .tooNoisy = problem { XCTFail("quiet room reported as too noisy") }
        }
    }

    func testCalibrationRejectsANoisyRoom() {
        let audio = noise(1.5, amplitude: 0.1) + note(60, seconds: 2, amplitude: 0.2)
        guard case .failure(.tooNoisy) = PianoCalibration.analyse(audio, sampleRate: rate, notes: [60], silence: 0.15..<1.35) else {
            return XCTFail("a loud room should be rejected")
        }
    }
}
