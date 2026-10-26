#if os(macOS)
import PianoGraderCore
import SwiftUI

/// Paints core `DrawItem`s into a SwiftUI `Canvas`.
enum DrawingPainter {
    static func color(_ ink: InkColor, _ paper: PP.Paper) -> Color {
        switch ink {
        case .ink: return paper.ink
        case .faint: return paper.faint
        case .cursor: return paper.accent.opacity(paper.isDark ? 0.32 : 0.22)
        case .audition: return paper.audition.opacity(paper.isDark ? 0.24 : 0.18)
        case .expectedHalo: return paper.accent.opacity(paper.isDark ? 0.32 : 0.22)
        case .expected: return paper.accent
        case .played: return paper.success
        case .wrong: return paper.mistake
        case .mistakeTint: return paper.mistake.opacity(paper.isDark ? 0.16 : 0.12)
        case .cleanTint: return paper.success.opacity(paper.isDark ? 0.12 : 0.08)
        case .playing: return paper.mistake.opacity(0.45)
        case .playedMark: return paper.success.opacity(0.5)
        }
    }

    static func path(_ elements: [PathElement], into path: inout Path) {
        for element in elements {
            switch element {
            case .move(let p): path.move(to: CGPoint(x: p.x, y: p.y))
            case .line(let p): path.addLine(to: CGPoint(x: p.x, y: p.y))
            case .quad(let p, let c): path.addQuadCurve(to: CGPoint(x: p.x, y: p.y), control: CGPoint(x: c.x, y: c.y))
            case .cubic(let p, let c1, let c2):
                path.addCurve(to: CGPoint(x: p.x, y: p.y), control1: CGPoint(x: c1.x, y: c1.y), control2: CGPoint(x: c2.x, y: c2.y))
            case .close: path.closeSubpath()
            }
        }
    }

    /// Draws items one by one, in order. For the few marks that change every frame.
    static func paint(_ items: [DrawItem], paper: PP.Paper, in context: inout GraphicsContext) {
        for item in items {
            switch item {
            case let .line(from, to, width, ink):
                var p = Path()
                p.move(to: CGPoint(x: from.x, y: from.y))
                p.addLine(to: CGPoint(x: to.x, y: to.y))
                context.stroke(p, with: .color(color(ink, paper)), lineWidth: width)
            case let .rect(x, y, width, height, radius, ink):
                let rect = CGRect(x: x, y: y, width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color(ink, paper)))
            case let .glyph(glyph, at, size, ink):
                var p = Path()
                path(glyph.elements(at: at, size: size), into: &p)
                context.fill(p, with: .color(color(ink, paper)))
            case let .shape(elements, ink):
                var p = Path()
                path(elements, into: &p)
                context.fill(p, with: .color(color(ink, paper)))
            case let .text(string, at, size, ink, anchor, bold):
                drawText(string, at: at, size: size, ink: ink, anchor: anchor, bold: bold, paper: paper, in: &context)
            }
        }
    }

    static func drawText(_ string: String, at: DrawPoint, size: Double, ink: InkColor, anchor: TextAnchor, bold: Bool,
                         paper: PP.Paper, in context: inout GraphicsContext) {
        let text = Text(string)
            .font(.system(size: size, weight: bold ? .bold : .regular))
            .foregroundColor(color(ink, paper))
        let unit: UnitPoint
        switch anchor {
        case .leading: unit = .bottomLeading
        case .center: unit = .bottom
        case .trailing: unit = .bottomTrailing
        }
        // The text box's bottom sits a little below the baseline; nudge it down to match.
        context.draw(text, at: CGPoint(x: at.x, y: at.y + size * 0.22), anchor: unit)
    }
}

/// A drawing merged into a few paths (one per colour, plus one per line width), so a whole
/// score paints quickly every frame while the playhead moves over it.
struct PaintedDrawing {
    struct Layer {
        var ink: InkColor
        var path: Path
        /// nil fills; a width strokes.
        var lineWidth: Double?
    }

    private(set) var layers: [Layer] = []
    private(set) var texts: [(String, DrawPoint, Double, InkColor, TextAnchor, Bool)] = []

    init(_ drawing: Drawing) {
        // Keep painting order where it matters: tints first, then everything else by colour.
        var order: [String] = []
        var byKey: [String: Layer] = [:]
        func layer(_ key: String, _ make: () -> Layer) -> String {
            if byKey[key] == nil {
                byKey[key] = make()
                order.append(key)
            }
            return key
        }
        for item in drawing.items {
            switch item {
            case let .line(from, to, width, ink):
                let key = layer("s\(ink.rawValue)\(width)") { Layer(ink: ink, path: Path(), lineWidth: width) }
                byKey[key]!.path.move(to: CGPoint(x: from.x, y: from.y))
                byKey[key]!.path.addLine(to: CGPoint(x: to.x, y: to.y))
            case let .rect(x, y, width, height, radius, ink):
                let key = layer("f\(ink.rawValue)") { Layer(ink: ink, path: Path(), lineWidth: nil) }
                byKey[key]!.path.addPath(Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: radius))
            case let .glyph(glyph, at, size, ink):
                let key = layer("f\(ink.rawValue)") { Layer(ink: ink, path: Path(), lineWidth: nil) }
                DrawingPainter.path(glyph.elements(at: at, size: size), into: &byKey[key]!.path)
            case let .shape(elements, ink):
                let key = layer("f\(ink.rawValue)") { Layer(ink: ink, path: Path(), lineWidth: nil) }
                DrawingPainter.path(elements, into: &byKey[key]!.path)
            case let .text(string, at, size, ink, anchor, bold):
                texts.append((string, at, size, ink, anchor, bold))
            }
        }
        layers = order.compactMap { byKey[$0] }
    }

    func paint(paper: PP.Paper, in context: inout GraphicsContext) {
        for layer in layers {
            if let width = layer.lineWidth {
                context.stroke(layer.path, with: .color(DrawingPainter.color(layer.ink, paper)), lineWidth: width)
            } else {
                context.fill(layer.path, with: .color(DrawingPainter.color(layer.ink, paper)))
            }
        }
        for t in texts {
            DrawingPainter.drawText(t.0, at: t.1, size: t.2, ink: t.3, anchor: t.4, bold: t.5, paper: paper, in: &context)
        }
    }
}
#endif
