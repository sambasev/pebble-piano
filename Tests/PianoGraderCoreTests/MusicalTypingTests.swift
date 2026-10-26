import XCTest
@testable import PianoGraderCore

final class MusicalTypingTests: XCTestCase {
    private func key(_ s: String) -> UInt8 { s.utf8.first! }

    func testHomeRowIsCMajorFromMiddleC() {
        var t = MusicalTyping()
        let pitches = "asdfghjk".map { ch -> Int? in
            if case let .note(pitch, _) = t.handle(key(String(ch))) { return pitch }
            return nil
        }
        XCTAssertEqual(pitches, [60, 62, 64, 65, 67, 69, 71, 72])
    }

    func testBlackKeys() {
        var t = MusicalTyping()
        XCTAssertEqual(t.handle(key("w")), .note(pitch: 61, velocity: 80))
        XCTAssertEqual(t.handle(key("e")), .note(pitch: 63, velocity: 80))
        XCTAssertEqual(t.handle(key("t")), .note(pitch: 66, velocity: 80))
        XCTAssertEqual(t.handle(key("p")), .note(pitch: 75, velocity: 80))
        XCTAssertEqual(t.handle(key("'")), .note(pitch: 77, velocity: 80))
    }

    func testCapsLockBehavesLikeLowercase() {
        var t = MusicalTyping()
        XCTAssertEqual(t.handle(key("A")), .note(pitch: 60, velocity: 80))
    }

    func testOctaveShiftAndClamp() {
        var t = MusicalTyping(octave: 4)
        XCTAssertEqual(t.handle(key("z")), .octave(3))
        XCTAssertEqual(t.handle(key("a")), .note(pitch: 48, velocity: 80))
        XCTAssertEqual(t.handle(key("x")), .octave(4))
        XCTAssertEqual(t.handle(key("x")), .octave(5))
        var high = MusicalTyping(octave: 8)
        XCTAssertEqual(high.handle(key("x")), .octave(8))
        XCTAssertEqual(high.handle(key("'")), .note(pitch: 125, velocity: 80)) // highest key stays in MIDI range
        XCTAssertEqual(high.handle(key("a")), .note(pitch: 108, velocity: 80))
    }

    func testVelocity() {
        var t = MusicalTyping(velocity: 80)
        XCTAssertEqual(t.handle(key("v")), .velocity(100))
        XCTAssertEqual(t.handle(key("v")), .velocity(120))
        XCTAssertEqual(t.handle(key("v")), .velocity(127))
        XCTAssertEqual(t.handle(key("c")), .velocity(107))
        XCTAssertEqual(t.handle(key("a")), .note(pitch: 60, velocity: 107))
    }

    func testControlKeys() {
        var t = MusicalTyping()
        XCTAssertEqual(t.handle(0x0D), .finish)
        XCTAssertEqual(t.handle(0x0A), .finish)
        XCTAssertEqual(t.handle(0x1B), .cancel)
        XCTAssertEqual(t.handle(key("q")), .ignored)
        XCTAssertEqual(t.handle(key("1")), .ignored)
    }

    func testDiagramLabelsFollowOctave() {
        var t = MusicalTyping()
        XCTAssertTrue(t.diagram.contains("[A]"))
        XCTAssertTrue(t.diagram.contains("C4"))
        XCTAssertTrue(t.diagram.contains("C#4"))
        _ = t.handle(UInt8(ascii: "z"))
        XCTAssertTrue(t.diagram.contains("C#3"))
        XCTAssertFalse(t.diagram.contains("C#5"))
    }
}
