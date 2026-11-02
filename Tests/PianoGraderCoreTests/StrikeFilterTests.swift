import XCTest
@testable import PianoGraderCore

final class StrikeFilterTests: XCTestCase {
    private func on(_ pitch: Int, conf: Double, strength: Double = 10, strike: Int = 1) -> DetectedNote {
        DetectedNote(kind: .on, pitch: pitch, time: 0, reportedAt: 0.05, confidence: conf, strength: strength, strike: strike)
    }

    private func off(_ pitch: Int) -> DetectedNote {
        DetectedNote(kind: .off, pitch: pitch, time: 0.2, reportedAt: 0.2)
    }

    func testDropsSpillAroundTheExpectedKey() {
        // From a real take: E4 expected; F4, F#4 and B2 lifted by the same strike.
        var filter = StrikeFilter()
        var reasons: [Int: StrikeFilter.Verdict] = [:]
        let kept = filter.filter([on(64, conf: 1), on(65, conf: 0.66), on(66, conf: 0.61), on(47, conf: 0.61)],
                                 expected: [64]) { reasons[$0.pitch] = $1 }
        XCTAssertEqual(kept.map(\.pitch), [64])
        XCTAssertEqual(reasons, [65: .spill, 66: .spill, 47: .spill])
    }

    func testKeepsAWrongKeyAsStrongAsTheExpectedOne() {
        var filter = StrikeFilter()
        let kept = filter.filter([on(64, conf: 1), on(65, conf: 0.95)], expected: [64])
        XCTAssertEqual(kept.map(\.pitch), [64, 65])
    }

    func testKeepsAWrongKeyStrongerThanTheExpectedOne() {
        // The wrong key was the strike; the expected one is its spill, but expected keys are kept.
        var filter = StrikeFilter()
        let kept = filter.filter([on(72, conf: 1), on(64, conf: 0.23)], expected: [64])
        XCTAssertEqual(kept.map(\.pitch), [72, 64])
    }

    func testKeepsUnexpectedKeysWhenNoExpectedKeySounded() {
        var filter = StrikeFilter()
        let kept = filter.filter([on(60, conf: 1), on(67, conf: 0.4)], expected: [64])
        XCTAssertEqual(kept.map(\.pitch), [60, 67])
    }

    func testOnlyComparesKeysOfTheSameStrike() {
        var filter = StrikeFilter()
        let kept = filter.filter([on(64, conf: 1, strike: 1), on(65, conf: 0.5, strike: 2)], expected: [64])
        XCTAssertEqual(kept.map(\.pitch), [64, 65])
    }

    func testDropsWeakUnexpectedStrikes() {
        var settings = StrikeFilter.Settings()
        settings.minimumStrength = 3
        var filter = StrikeFilter(settings: settings)
        let kept = filter.filter([on(46, conf: 1, strength: 1.2)], expected: [64])
        XCTAssertTrue(kept.isEmpty)
        // An expected key is kept however weak.
        XCTAssertEqual(filter.filter([on(64, conf: 1, strength: 1.2, strike: 2)], expected: [64]).map(\.pitch), [64])
    }

    func testDropsTheReleaseOfADroppedKey() {
        var filter = StrikeFilter()
        _ = filter.filter([on(64, conf: 1), on(65, conf: 0.5)], expected: [64])
        XCTAssertEqual(filter.filter([off(65), off(64)], expected: [64]).map(\.pitch), [64])
    }

    func testAReStrikeOfADroppedKeyIsReportedWhole() {
        var filter = StrikeFilter()
        _ = filter.filter([on(64, conf: 1), on(65, conf: 0.5)], expected: [64])
        // The detector ends the old note and starts the new one in the same batch.
        let kept = filter.filter([off(65), on(65, conf: 1, strike: 2)], expected: [64])
        XCTAssertEqual(kept.map(\.kind), [.on])
        XCTAssertEqual(filter.filter([off(65)], expected: [64]).count, 1)
    }

    func testDetectorTagsStrikesAndStrength() {
        let rate = 48000.0
        var audio = [Float](repeating: 0, count: Int(1.2 * rate))
        for pitch in [60, 64] {
            let f0 = 440 * pow(2, Double(pitch - 69) / 12)
            for h in 1...8 {
                let f = Double(h) * f0
                for i in Int(0.5 * rate)..<audio.count {
                    let t = Double(i) / rate - 0.5
                    audio[i] += Float(0.06 / Double(h) * exp(-t * 2) * sin(2 * Double.pi * f * t))
                }
            }
        }
        for i in audio.indices { audio[i] += Float((i * 7919) % 1000) / 1000 * 0.0004 - 0.0002 }
        let detector = PianoNoteDetector(sampleRate: rate)
        detector.expected = [60, 64]
        var ons: [DetectedNote] = []
        var i = 0
        while i < audio.count {
            let end = min(audio.count, i + 256)
            ons += detector.process(Array(audio[i..<end])).filter { $0.kind == .on }
            i = end
        }
        XCTAssertEqual(Set(ons.map(\.pitch)), [60, 64])
        XCTAssertEqual(Set(ons.map(\.strike)).count, 1, "one strike")
        XCTAssertTrue(ons.allSatisfy { $0.strength >= detector.settings.minimumRise && $0.strength.isFinite })
    }

    func testReadsARecordingThatWasNeverClosed() throws {
        // RIFF/WAVE, 32-bit float mono fmt, then a data chunk whose size was never filled in.
        var bytes: [UInt8] = Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WAVE".utf8)
        func u32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        func u16(_ v: Int) -> [UInt8] { (0..<2).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        bytes += Array("fmt ".utf8) + u32(16) + u16(3) + u16(1) + u32(16000) + u32(64000) + u16(4) + u16(32)
        bytes += Array("data".utf8) + u32(0)
        for v: Float in [0.25, -0.5, 1] { bytes += u32(Int(v.bitPattern)) }
        let audio = try WAVFile.parse(Data(bytes))
        XCTAssertEqual(audio.samples, [0.25, -0.5, 1])
    }
}
