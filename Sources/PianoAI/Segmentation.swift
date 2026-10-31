import Foundation

/// One object SAM 3.1 found: its box in source pixels, and its mask's size.
/// Mask payloads aren't decoded; finding systems on a page only needs the boxes.
public struct Segment: Equatable, Sendable {
    public struct Box: Equatable, Sendable {
        public var x1: Int, y1: Int, x2: Int, y2: Int
        public var width: Int { x2 - x1 }
        public var height: Int { y2 - y1 }
        public init(x1: Int, y1: Int, x2: Int, y2: Int) { self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2 }
    }

    public var frame: Int
    /// Stable per response; not dense or zero-based.
    public var objectID: Int
    public var box: Box
    /// The source image size, as SAM reports it.
    public var imageWidth: Int
    public var imageHeight: Int
    /// 0–1, only when the request asked for confidence.
    public var confidence: Double?
    public var maskRows: Int?
    public var maskColumns: Int?
}

/// Parses SAM 3.1's special-token output (see dev.meta.ai/docs/sam/reading-segmentation):
///
///     <0f>0<|box;x1=..;y1=..;x2=..;y2=..;w=..;h=..[;c=..]|><|mask;x=0;y=0[;c=..];data=H,W,~payload|>,1<|box;...
///
/// The mask payload is base85 and may contain `|` and `>`, so records are split where a
/// comma is followed by `<id><|box;`. Base85 has no comma, so that only happens between records.
public enum SegmentationOutput {
    public static func parse(_ text: String) -> [Segment] {
        text.split(whereSeparator: \.isNewline).flatMap { parseLine(String($0)) }
    }

    static func parseLine(_ line: String) -> [Segment] {
        guard let frameMatch = line.firstMatch(of: #/^<(\d+)f>/#), let frame = Int(frameMatch.1) else { return [] }
        let rest = line[frameMatch.range.upperBound...]
        let starts = Array(rest.matches(of: #/(?:^|,)(\d+)<\|box;([^|]*)\|>/#))
        var segments: [Segment] = []
        for (i, m) in starts.enumerated() {
            guard let id = Int(m.1) else { continue }
            let box = fields(String(m.2))
            guard let x1 = box["x1"].flatMap(Int.init), let y1 = box["y1"].flatMap(Int.init),
                  let x2 = box["x2"].flatMap(Int.init), let y2 = box["y2"].flatMap(Int.init)
            else { continue }
            let maskEnd = i + 1 < starts.count ? starts[i + 1].range.lowerBound : rest.endIndex
            let maskText = rest[m.range.upperBound..<maskEnd]
            var rows: Int?, cols: Int?, maskConfidence: Double?
            if maskText.hasPrefix("<|mask;"), let dataRange = maskText.range(of: "data=") {
                let header = fields(String(maskText[maskText.index(maskText.startIndex, offsetBy: 7)..<dataRange.lowerBound]))
                maskConfidence = header["c"].flatMap(Double.init)
                let dims = maskText[dataRange.upperBound...].split(separator: ",", maxSplits: 2)
                if dims.count >= 2 { rows = Int(dims[0]); cols = Int(dims[1]) }
            }
            segments.append(Segment(
                frame: frame, objectID: id, box: .init(x1: x1, y1: y1, x2: x2, y2: y2),
                imageWidth: box["w"].flatMap(Int.init) ?? 0, imageHeight: box["h"].flatMap(Int.init) ?? 0,
                confidence: box["c"].flatMap(Double.init) ?? maskConfidence,
                maskRows: rows, maskColumns: cols))
        }
        return segments
    }

    /// `k=v;k=v` pairs, read by key so an optional `c` doesn't shift anything.
    static func fields(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for part in s.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { out[String(kv[0])] = String(kv[1]) }
        }
        return out
    }
}
