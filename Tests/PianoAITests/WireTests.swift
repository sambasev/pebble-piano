import XCTest
@testable import PianoAI

final class WireTests: XCTestCase {
    func testWAVHeader() {
        let wav = WAV.encode(samples: [0, 100, -100, 0], sampleRate: 24_000)
        XCTAssertEqual(wav.count, 44 + 8)
        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
        let rate = wav[24..<28].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        XCTAssertEqual(rate, 24_000)
        XCTAssertEqual(wav[22], 1, "mono")
        XCTAssertEqual(wav[34], 16, "16-bit")
    }

    func testResamplesFloatsTo24k() {
        let oneSecondAt48k = [Float](repeating: 0.5, count: 48_000)
        let wav = WAV.encode(floats: oneSecondAt48k, sampleRate: 48_000)
        XCTAssertEqual((wav.count - 44) / 2, 24_000)
    }

    func testServerSentEvents() {
        let body = Data("event: a\ndata: {\"x\":1}\n\n: comment\r\ndata: line1\ndata: line2\r\n\r\ndata: [DONE]\n\n".utf8)
        XCTAssertEqual(ServerSentEvents.dataPayloads(body), ["{\"x\":1}", "line1\nline2"])
    }

    func testJSONValueRoundTripKeepsBoolsAndInts() throws {
        let v: JSONValue = ["a": true, "b": 3, "c": 2.5, "d": ["x", nil]]
        let back = try JSONValue(parsing: try v.data())
        XCTAssertEqual(back, v)
        XCTAssertEqual(String(decoding: try JSONValue.object(["n": 3]).data(), as: UTF8.self), #"{"n":3}"#)
    }
}
