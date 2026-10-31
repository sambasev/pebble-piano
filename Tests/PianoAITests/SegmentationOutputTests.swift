import XCTest
@testable import PianoAI

final class SegmentationOutputTests: XCTestCase {
    func testDocsImageExample() {
        let line = "<0f>0<|box;x1=353;y1=382;x2=453;y2=427;w=537;h=561|><|mask;x=0;y=0;data=46,101,~abc|>,"
            + "1<|box;x1=260;y1=382;x2=340;y2=427;w=537;h=561|><|mask;x=0;y=0;data=46,81,~def|>,"
            + "2<|box;x1=516;y1=117;x2=536;y2=150;w=537;h=561|><|mask;x=0;y=0;data=34,21,~ghi|>"
        let s = SegmentationOutput.parse(line)
        XCTAssertEqual(s.map(\.objectID), [0, 1, 2])
        XCTAssertEqual(s[0].box, .init(x1: 353, y1: 382, x2: 453, y2: 427))
        XCTAssertEqual(s[0].imageWidth, 537)
        XCTAssertEqual(s[0].imageHeight, 561)
        XCTAssertEqual(s[1].maskRows, 46)
        XCTAssertEqual(s[1].maskColumns, 81)
        XCTAssertNil(s[2].confidence)
    }

    func testPayloadContainingPipesAndBracketsDoesNotSplitRecords() {
        // RFC 1924 base85 can contain |, >, <, ~ and !, but never a comma.
        let line = "<0f>4<|box;x1=1;y1=2;x2=3;y2=4;w=10;h=10|><|mask;x=0;y=0;data=2,2,~a|>b<|box;c|>,"
            + "7<|box;x1=5;y1=6;x2=7;y2=8;w=10;h=10|><|mask;x=0;y=0;data=2,2,!z|>"
        let s = SegmentationOutput.parse(line)
        XCTAssertEqual(s.map(\.objectID), [4, 7])
        XCTAssertEqual(s[1].box, .init(x1: 5, y1: 6, x2: 7, y2: 8))
    }

    func testConfidenceReadByKey() {
        let line = "<0f>1<|box;x1=444;y1=625;x2=679;y2=850;w=1800;h=1200;c=0.9609375|><|mask;x=0;y=0;c=0.9609375;data=226,236,!xyz|>"
        let s = SegmentationOutput.parse(line)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].confidence ?? 0, 0.9609375, accuracy: 1e-9)
        XCTAssertEqual(s[0].maskRows, 226)
    }

    func testVideoLinesAndEmptyOutput() {
        let text = "<0f>0<|box;x1=1;y1=1;x2=2;y2=2;w=9;h=9|><|mask;x=0;y=0;data=1,1,~a|>\n"
            + "<2f>0<|box;x1=3;y1=3;x2=4;y2=4;w=9;h=9|><|mask;x=0;y=0;data=1,1,~b|>"
        XCTAssertEqual(SegmentationOutput.parse(text).map(\.frame), [0, 2])
        XCTAssertEqual(SegmentationOutput.parse(""), [])
    }
}
