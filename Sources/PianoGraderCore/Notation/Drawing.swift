import Foundation

/// A point in drawing space: points, y grows downwards (as on screen).
public struct DrawPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

/// One piece of a path outline.
public enum PathElement: Equatable, Sendable {
    case move(DrawPoint)
    case line(DrawPoint)
    case quad(DrawPoint, control: DrawPoint)
    case cubic(DrawPoint, control1: DrawPoint, control2: DrawPoint)
    case close
}

/// What a mark means; the app and the SVG writer each pick the actual colour.
public enum InkColor: String, Sendable {
    /// Engraving: staff lines, notes, symbols.
    case ink
    /// Secondary text such as measure numbers.
    case faint
    /// The playhead band.
    case cursor
    /// The playhead while the reference plays.
    case audition
    /// A soft disc behind each note the guide is waiting for, so it can't be missed.
    case expectedHalo
    /// Notes the guide is waiting for (blue, like the playhead).
    case expected
    /// Notes already played correctly.
    case played
    /// Notes played that the guide did not expect.
    case wrong
    /// Measure tint after grading: had mistakes.
    case mistakeTint
    /// Measure tint after grading: clean.
    case cleanTint
    /// A key being held that the guide did not expect: a see-through mark on the staff.
    case playing
    /// A see-through green mark over a printed note that was played correctly (book pages).
    case playedMark
}

public enum TextAnchor: Sendable { case leading, center, trailing }

/// One drawing instruction. Everything a score needs reduces to these.
public enum DrawItem: Sendable {
    case line(from: DrawPoint, to: DrawPoint, width: Double, color: InkColor)
    case rect(x: Double, y: Double, width: Double, height: Double, cornerRadius: Double, color: InkColor)
    /// A music symbol with its origin at `at`, scaled so one staff space is `size` points.
    case glyph(Glyph, at: DrawPoint, size: Double, color: InkColor)
    /// A filled outline already in drawing space (beams, ties).
    case shape([PathElement], color: InkColor)
    /// Text with its baseline at `at.y`.
    case text(String, at: DrawPoint, size: Double, color: InkColor, anchor: TextAnchor, bold: Bool)
}

/// A finished drawing: its size and items in painting order.
public struct Drawing: Sendable {
    public var width: Double
    public var height: Double
    public var items: [DrawItem]

    public init(width: Double, height: Double, items: [DrawItem]) {
        self.width = width
        self.height = height
        self.items = items
    }
}

extension Glyph {
    private static let outlines: [Glyph: [PathElement]] = {
        var all: [Glyph: [PathElement]] = [:]
        for glyph in Glyph.allCases { all[glyph] = SVGPathParser.parse(glyph.path) }
        return all
    }()

    /// The outline in staff spaces, y up.
    public var elements: [PathElement] { Self.outlines[self] ?? [] }

    public var width: Double { bounds.maxX - bounds.minX }

    /// The outline placed in drawing space: origin at `origin`, one staff space = `size` points.
    public func elements(at origin: DrawPoint, size: Double) -> [PathElement] {
        func map(_ p: DrawPoint) -> DrawPoint { DrawPoint(origin.x + p.x * size, origin.y - p.y * size) }
        return elements.map { e in
            switch e {
            case .move(let p): return .move(map(p))
            case .line(let p): return .line(map(p))
            case .quad(let p, let c): return .quad(map(p), control: map(c))
            case .cubic(let p, let c1, let c2): return .cubic(map(p), control1: map(c1), control2: map(c2))
            case .close: return .close
            }
        }
    }
}

/// Reads the absolute M/L/H/V/Q/C/Z path data the glyph table uses.
enum SVGPathParser {
    static func parse(_ d: String) -> [PathElement] {
        var tokens: [String] = []
        var number = ""
        func flush() { if !number.isEmpty { tokens.append(number); number = "" } }
        for c in d {
            if c.isLetter && c != "e" && c != "E" {
                flush()
                tokens.append(String(c))
            } else if c == " " || c == "," {
                flush()
            } else if c == "-" && !number.isEmpty && !(number.last == "e" || number.last == "E") {
                flush()
                number = "-"
            } else {
                number.append(c)
            }
        }
        flush()

        var elements: [PathElement] = []
        var i = 0
        var command = "M"
        var current = DrawPoint(0, 0)
        func value() -> Double {
            defer { i += 1 }
            return i < tokens.count ? Double(tokens[i]) ?? 0 : 0
        }
        func point() -> DrawPoint { let x = value(); return DrawPoint(x, value()) }
        while i < tokens.count {
            if let first = tokens[i].first, first.isLetter {
                command = tokens[i]
                i += 1
                if command == "Z" || command == "z" {
                    elements.append(.close)
                    continue
                }
            }
            switch command {
            case "M":
                current = point()
                elements.append(.move(current))
                command = "L" // further pairs are line-tos
            case "L":
                current = point()
                elements.append(.line(current))
            case "H":
                current = DrawPoint(value(), current.y)
                elements.append(.line(current))
            case "V":
                current = DrawPoint(current.x, value())
                elements.append(.line(current))
            case "Q":
                let c = point()
                current = point()
                elements.append(.quad(current, control: c))
            case "C":
                let c1 = point(), c2 = point()
                current = point()
                elements.append(.cubic(current, control1: c1, control2: c2))
            default:
                i += 1 // unsupported command: skip its value
            }
        }
        return elements
    }
}

// MARK: - SVG

extension Drawing {
    /// The drawing as a standalone SVG document (white paper, black ink).
    public func svg() -> String {
        func f(_ v: Double) -> String { String(format: "%.2f", v) }
        func colour(_ c: InkColor) -> (String, Double) {
            switch c {
            case .ink: return ("#000000", 1)
            case .faint: return ("#6b6b6b", 1)
            case .cursor: return ("#1f6feb", 0.22)
            case .audition: return ("#8a3ffc", 0.18)
            case .expectedHalo: return ("#1f6feb", 0.22)
            case .expected: return ("#1f6feb", 1)
            case .played: return ("#1a8f3c", 1)
            case .wrong: return ("#d1242f", 1)
            case .mistakeTint: return ("#d1242f", 0.12)
            case .cleanTint: return ("#1a8f3c", 0.08)
            case .playing: return ("#d1242f", 0.45)
            case .playedMark: return ("#1a8f3c", 0.5)
            }
        }
        func pathData(_ elements: [PathElement]) -> String {
            elements.map { e -> String in
                switch e {
                case .move(let p): return "M\(f(p.x)) \(f(p.y))"
                case .line(let p): return "L\(f(p.x)) \(f(p.y))"
                case .quad(let p, let c): return "Q\(f(c.x)) \(f(c.y)) \(f(p.x)) \(f(p.y))"
                case .cubic(let p, let c1, let c2): return "C\(f(c1.x)) \(f(c1.y)) \(f(c2.x)) \(f(c2.y)) \(f(p.x)) \(f(p.y))"
                case .close: return "Z"
                }
            }.joined()
        }
        var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(f(width))\" height=\"\(f(height))\" viewBox=\"0 0 \(f(width)) \(f(height))\">\n"
        out += "<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n"
        for item in items {
            switch item {
            case let .line(a, b, w, c):
                let (hex, o) = colour(c)
                out += "<line x1=\"\(f(a.x))\" y1=\"\(f(a.y))\" x2=\"\(f(b.x))\" y2=\"\(f(b.y))\" stroke=\"\(hex)\" stroke-opacity=\"\(o)\" stroke-width=\"\(f(w))\"/>\n"
            case let .rect(x, y, w, h, r, c):
                let (hex, o) = colour(c)
                out += "<rect x=\"\(f(x))\" y=\"\(f(y))\" width=\"\(f(w))\" height=\"\(f(h))\" rx=\"\(f(r))\" fill=\"\(hex)\" fill-opacity=\"\(o)\"/>\n"
            case let .glyph(g, at, size, c):
                let (hex, o) = colour(c)
                out += "<path d=\"\(pathData(g.elements(at: at, size: size)))\" fill=\"\(hex)\" fill-opacity=\"\(o)\"/>\n"
            case let .shape(elements, c):
                let (hex, o) = colour(c)
                out += "<path d=\"\(pathData(elements))\" fill=\"\(hex)\" fill-opacity=\"\(o)\"/>\n"
            case let .text(s, at, size, c, anchor, bold):
                let (hex, o) = colour(c)
                let a = anchor == .leading ? "start" : (anchor == .center ? "middle" : "end")
                out += "<text x=\"\(f(at.x))\" y=\"\(f(at.y))\" font-family=\"Helvetica, Arial, sans-serif\" font-size=\"\(f(size))\" font-weight=\"\(bold ? "bold" : "normal")\" text-anchor=\"\(a)\" fill=\"\(hex)\" fill-opacity=\"\(o)\">\(XMLBuilder.escape(s))</text>\n"
            }
        }
        out += "</svg>\n"
        return out
    }
}
