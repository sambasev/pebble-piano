import XCTest
@testable import PianoLessons

final class ChildModeTests: XCTestCase {
    func testStickerPerPageWraps() {
        XCTAssertEqual(Stickers.forPage(at: 0), Stickers.all[0])
        XCTAssertEqual(Stickers.forPage(at: Stickers.all.count + 2), Stickers.all[2])
        XCTAssertEqual(Stickers.forPage(at: -1), Stickers.all.last)
        XCTAssertEqual(Set(Stickers.all.map(\.symbol)).count, Stickers.all.count, "each sticker is different")
    }

    func testCheerHasNoNumbers() {
        for stars in 0...3 {
            XCTAssertNil(Stickers.cheer(stars: stars).rangeOfCharacter(from: .decimalDigits))
        }
    }

    func testTipOrder() {
        var f = GrownUpsTip.Facts(name: "Mia", minutesThisWeek: 0, daysThisWeek: 0, stuckPage: "Meet E",
                                  usesComputerKeyboard: true, goalSong: "Jingle Bells")
        XCTAssertTrue(GrownUpsTip.tip(f).hasPrefix("A good time to start"))
        f.minutesThisWeek = 20
        f.daysThisWeek = 1
        XCTAssertTrue(GrownUpsTip.tip(f).contains("Meet E"))
        f.stuckPage = nil
        XCTAssertTrue(GrownUpsTip.tip(f).hasPrefix("Short and often"))
        f.daysThisWeek = 4
        XCTAssertTrue(GrownUpsTip.tip(f).contains("real piano"))
        f.usesComputerKeyboard = false
        XCTAssertTrue(GrownUpsTip.tip(f).contains("Jingle Bells"))
        f.goalSong = nil
        XCTAssertTrue(GrownUpsTip.tip(f).contains("what they learned"))
    }
}
