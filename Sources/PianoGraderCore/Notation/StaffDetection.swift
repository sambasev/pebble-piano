import Foundation

/// Where a printed staff sits on a book page, in PDF page space (points, y grows upwards).
public struct StaffPlacement: Codable, Equatable, Sendable {
    /// y of the bottom staff line.
    public var bottomLineY: Double
    /// Distance between neighbouring staff lines.
    public var spacing: Double

    public init(bottomLineY: Double, spacing: Double) {
        self.bottomLineY = bottomLineY
        self.spacing = spacing
    }

    public var topLineY: Double { bottomLineY + 4 * spacing }

    /// y of a line or space: step 0 is the bottom line, 1 the space above it, 8 the top line.
    /// Steps below 0 and above 8 are on ledger lines.
    public func y(ofStep step: Int) -> Double {
        bottomLineY + Double(step) * spacing / 2
    }
}

/// A greyscale image: one byte per pixel, row by row from the top, 0 = black, 255 = white.
public struct GrayImage: Sendable {
    public var width: Int
    public var height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height, "pixel count must be width × height")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public subscript(x: Int, y: Int) -> UInt8 { pixels[y * width + x] }
}

/// A staff found in an image: its five lines, top to bottom, in pixel rows.
public struct DetectedStaff: Equatable, Sendable {
    public var lineYs: [Double]

    public var top: Double { lineYs.first ?? 0 }
    public var bottom: Double { lineYs.last ?? 0 }
    public var spacing: Double { lineYs.count > 1 ? (bottom - top) / Double(lineYs.count - 1) : 0 }
}

/// Finds printed five-line staves in a rendered page, so played notes can be drawn on
/// the book's own staff. Staff lines are the rows that are dark across most of a measure;
/// noteheads, stems and text are too short to count.
public enum StaffLineDetector {
    /// - Parameters:
    ///   - region: pixel rectangle to search (x0..<x1, y0..<y1), usually one measure.
    ///   - coverage: share of the region's width a row must be dark across to be a line.
    public static func detect(in image: GrayImage, x0: Int, x1: Int, y0: Int, y1: Int,
                              darkThreshold: UInt8 = 140, coverage: Double = 0.6) -> [DetectedStaff] {
        let left = max(0, min(x0, x1)), right = min(image.width, max(x0, x1))
        let top = max(0, min(y0, y1)), bottom = min(image.height, max(y0, y1))
        guard right - left >= 8, bottom - top >= 8 else { return [] }

        // 1. Rows dark across most of the width.
        let width = right - left
        var lineRows: [Int] = []
        for y in top..<bottom {
            var dark = 0
            for x in left..<right where image[x, y] < darkThreshold { dark += 1 }
            if Double(dark) >= coverage * Double(width) { lineRows.append(y) }
        }

        // 2. A thick line covers several neighbouring rows: take each run's centre.
        var lines: [Double] = []
        var runStart: Int? = nil
        var previous = -10
        for y in lineRows {
            if y != previous + 1 {
                if let s = runStart { lines.append(Double(s + previous) / 2) }
                runStart = y
            }
            previous = y
        }
        if let s = runStart { lines.append(Double(s + previous) / 2) }

        // 3. Five lines in a row with even spacing make a staff.
        var staves: [DetectedStaff] = []
        var i = 0
        while i + 4 < lines.count {
            let group = Array(lines[i...(i + 4)])
            let gaps = zip(group.dropFirst(), group).map { $0 - $1 }
            let mean = gaps.reduce(0, +) / 4
            if mean >= 3, gaps.allSatisfy({ abs($0 - mean) <= max(1.5, 0.2 * mean) }) {
                staves.append(DetectedStaff(lineYs: group))
                i += 5
            } else {
                i += 1
            }
        }
        return staves
    }
}
