import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif
#if canImport(PDFKit)
import PDFKit
#endif

/// A system found on a page: an upper and a lower staff, in page pixels.
public struct FoundSystem: Codable, Equatable, Sendable {
    /// From 0, top to bottom on the page.
    public var index: Int
    public var left: Int
    public var top: Int
    public var right: Int
    public var bottom: Int
    /// Staff line spacing, in pixels.
    public var spacing: Double

    public init(index: Int, left: Int, top: Int, right: Int, bottom: Int, spacing: Double) {
        self.index = index
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
        self.spacing = spacing
    }

    public var width: Int { right - left }
    public var height: Int { bottom - top }
}

/// Finds the systems on a page by their staff lines, and cuts them out for reading.
/// Beginner piano music is written on grand staves, so staves are paired top to bottom.
public enum SystemFinder {
    public static func find(in page: Gray) -> [FoundSystem] {
        let ink = NoteheadGeometry.deskew(page.binarized())
        // Five evenly spaced lines of text can look like a staff: keep staves whose line spacing
        // matches the page's usual spacing.
        let found = NoteheadGeometry.staffLines(ink)
        guard !found.isEmpty else { return [] }
        let median = found.map(\.spacing).sorted()[found.count / 2]
        let staves = found.filter { abs($0.spacing - median) <= 0.25 * median }
        var systems: [FoundSystem] = []
        var i = 0
        while i + 1 < staves.count {
            let upper = staves[i], lower = staves[i + 1]
            let sp = (upper.spacing + lower.spacing) / 2
            // The two staves of a grand staff are closer together than one system is to the
            // next. If this gap is clearly the wider one, staff i stands alone: skip it.
            let gap = lower.top - upper.bottom
            if i + 2 < staves.count, gap > 1.3 * (staves[i + 2].top - lower.bottom) { i += 1; continue }
            // Left and right ends of the staff lines.
            let rows = upper.lines.map { Int($0.rounded()) }
            var minX = Int.max, maxX = 0
            for x in 0..<ink.width where rows.filter({ ink[x, $0] }).count >= 4 {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
            guard minX < maxX else { i += 2; continue }
            let margin = Int((0.5 * sp).rounded())
            systems.append(FoundSystem(
                index: systems.count,
                left: max(0, minX - margin), top: max(0, Int(upper.top - 3.5 * sp)),
                right: min(page.width, maxX + margin), bottom: min(page.height, Int(lower.bottom + 3.5 * sp)),
                spacing: sp))
            i += 2
        }
        // Neighbouring systems mustn't overlap: meet halfway.
        for k in systems.indices.dropFirst() where systems[k].top < systems[k - 1].bottom {
            let middle = (systems[k].top + systems[k - 1].bottom) / 2
            systems[k - 1].bottom = middle
            systems[k].top = middle
        }
        return systems
    }

    public static func crop(_ page: Gray, _ s: FoundSystem) -> Gray {
        var pixels = [UInt8](repeating: 255, count: s.width * s.height)
        for y in 0..<s.height {
            let src = (s.top + y) * page.width + s.left
            for x in 0..<s.width { pixels[y * s.width + x] = page.pixels[src + x] }
        }
        return Gray(width: s.width, height: s.height, pixels: pixels)
    }
}

#if canImport(CoreGraphics)
extension Gray {
    public func cgImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    public func pngData() -> Data? {
        guard let image = cgImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
#endif

#if canImport(PDFKit) && canImport(CoreGraphics)
/// Renders the pages of an imported book.
public enum BookImporter {
    /// Resolution pages are read at (the probes used 220 dpi system crops).
    public static let dpi: Double = 220

    public static func render(_ page: PDFPage, dpi: Double = dpi) -> Gray? {
        let box = page.bounds(for: .mediaBox)
        let scale = dpi / 72
        let w = Int((box.width * scale).rounded()), h = Int((box.height * scale).rounded())
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 255, count: w * h)
        let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            page.draw(with: .mediaBox, to: ctx)
            return true
        }
        return ok ? Gray(width: w, height: h, pixels: pixels) : nil
    }

    /// Page `index` (from 0) of a PDF, rendered and with its systems found.
    public static func page(_ document: PDFDocument, index: Int) -> (image: Gray, systems: [FoundSystem])? {
        guard let page = document.page(at: index), let image = render(page) else { return nil }
        return (image, SystemFinder.find(in: image))
    }
}
#endif
