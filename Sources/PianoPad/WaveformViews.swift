#if os(macOS)
import PianoGraderCore
import SwiftUI

/// The detailed waveform: the visible window of the file with the bar grid, trim regions,
/// bar 1, the cursor and the playhead. Drag a marker (trim start, bar 1, trim end) to move it;
/// click or drag anywhere else to place the cursor.
struct WaveformDetailView: View {
    @ObservedObject var model: BackingEditorModel
    @State private var dragging: BackingEditorModel.Marker?

    private static let handleSlop: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .background(PP.surfaceRaised)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragging == nil { dragging = marker(near: value.startLocation.x, width: size.width) }
                        model.move(dragging ?? .cursor, to: time(at: value.location.x, width: size.width))
                    }
                    .onEnded { _ in dragging = nil }
            )
            .overlay(alignment: .topLeading) { legend.padding(6) }
        }
        .clipShape(RoundedRectangle(cornerRadius: PP.Radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PP.Radius.sm, style: .continuous).stroke(PP.inkStaff.opacity(0.4)))
    }

    private var legend: some View {
        HStack(spacing: 10) {
            label("Trim", PP.inkStaff)
            label("Bar 1", PP.accent)
            label("Cursor", PP.warning)
        }
        .font(.caption2)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .allowsHitTesting(false)
    }

    private func label(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 3, height: 10)
            Text(text)
        }
    }

    // MARK: Geometry

    private func x(_ t: Double, width: CGFloat) -> CGFloat {
        CGFloat((t - model.viewStart) / max(1e-6, model.viewSpan)) * width
    }

    private func time(at x: CGFloat, width: CGFloat) -> Double {
        model.viewStart + Double(x / max(1, width)) * model.viewSpan
    }

    /// The marker under a point, if one is within reach (bar 1 first: it matters most).
    private func marker(near px: CGFloat, width: CGFloat) -> BackingEditorModel.Marker? {
        guard let track = model.draft else { return nil }
        let candidates: [(BackingEditorModel.Marker, Double)] = [
            (.bar1, track.bar1Seconds), (.trimStart, track.trimStart), (.trimEnd, track.playEnd),
        ]
        return candidates
            .map { ($0.0, abs(x($0.1, width: width) - px)) }
            .filter { $0.1 <= Self.handleSlop }
            .min { $0.1 < $1.1 }?.0
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height, mid = h / 2
        guard let track = model.draft else { return }

        // Waveform.
        if let peaks = model.peaks {
            let columns = max(1, Int(w))
            let cols = peaks.columns(from: model.viewStart, to: model.viewStart + model.viewSpan, count: columns)
            let scale = CGFloat(1 / max(0.05, peaks.peak)) * (h * 0.45)
            var path = Path()
            for (i, c) in cols.enumerated() {
                let px = CGFloat(i) + 0.5
                path.move(to: CGPoint(x: px, y: mid - CGFloat(c.max) * scale))
                path.addLine(to: CGPoint(x: px, y: mid - CGFloat(c.min) * scale + 0.5))
            }
            context.stroke(path, with: .color(PP.accent.opacity(0.85)), lineWidth: 1)
        } else {
            context.draw(Text(model.loadingProgress.map { "Reading audio… \(Int($0 * 100))%" } ?? "No waveform")
                .foregroundColor(PP.inkMuted), at: CGPoint(x: w / 2, y: mid))
        }

        // Trimmed-off regions, greyed.
        let xs = x(track.trimStart, width: w), xe = x(track.playEnd, width: w)
        if xs > 0 { context.fill(Path(CGRect(x: 0, y: 0, width: xs, height: h)), with: .color(PP.inkStaff.opacity(0.35))) }
        if xe < w { context.fill(Path(CGRect(x: xe, y: 0, width: w - xe, height: h)), with: .color(PP.inkStaff.opacity(0.35))) }

        // Beat ticks and bar lines with numbers, when they're far enough apart to read.
        let barPx = CGFloat(track.barSeconds / model.viewSpan) * w
        let beatPx = CGFloat(track.beatSeconds / model.viewSpan) * w
        let labelEvery = max(1, Int((40 / max(1, barPx)).rounded(.up)))
        for line in track.barLines() {
            let bx = x(line.seconds, width: w)
            guard bx >= -40, bx <= w + 40 else { continue }
            if beatPx >= 6 {
                for b in 1..<max(1, track.timeSignature.numerator) {
                    let tx = bx + CGFloat(b) * beatPx
                    context.stroke(Path { $0.move(to: CGPoint(x: tx, y: h - 8)); $0.addLine(to: CGPoint(x: tx, y: h)) },
                                   with: .color(PP.inkStaff.opacity(0.5)), lineWidth: 1)
                }
            }
            guard barPx >= 4 else { continue }
            let isBar1 = line.bar == 1
            if !isBar1 {
                context.stroke(Path { $0.move(to: CGPoint(x: bx, y: 14)); $0.addLine(to: CGPoint(x: bx, y: h)) },
                               with: .color(PP.inkStaff.opacity(line.bar < 1 ? 0.25 : 0.5)), lineWidth: 1)
            }
            if (line.bar - 1) % labelEvery == 0 && !isBar1 {
                context.draw(Text("\(line.bar)").font(.caption2).foregroundColor(PP.inkMuted),
                             at: CGPoint(x: bx + 3, y: 8), anchor: .leading)
            }
        }

        // Trim handles.
        for (tx, color) in [(xs, PP.inkStaff), (xe, PP.inkStaff)] where tx >= -2 && tx <= w + 2 {
            context.fill(Path(CGRect(x: tx - 1.5, y: 0, width: 3, height: h)), with: .color(color))
        }
        // Bar 1.
        let b1 = x(track.bar1Seconds, width: w)
        if b1 >= -2, b1 <= w + 2 {
            context.fill(Path(CGRect(x: b1 - 1.5, y: 0, width: 3, height: h)), with: .color(PP.accent))
            context.draw(Text("Bar 1").font(.caption.weight(.bold)).foregroundColor(PP.accent),
                         at: CGPoint(x: b1 + 5, y: 8), anchor: .leading)
        }
        // Cursor and playhead.
        let cx = x(model.cursor, width: w)
        context.fill(Path(CGRect(x: cx - 1, y: 0, width: 2, height: h)), with: .color(PP.warning))
        if let p = model.playhead {
            let px = x(p, width: w)
            context.fill(Path(CGRect(x: px - 1, y: 0, width: 2, height: h)), with: .color(PP.success))
        }
    }
}

/// The whole file, small, with the visible window outlined. Click or drag to move the window.
struct WaveformOverviewView: View {
    @ObservedObject var model: BackingEditorModel

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    let t = Double(value.location.x / max(1, geo.size.width)) * model.duration
                    model.scroll(to: t - model.viewSpan / 2)
                }
            )
        }
        .background(PP.surfaceRaised.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height, mid = h / 2
        let total = max(1e-6, model.duration)
        func x(_ t: Double) -> CGFloat { CGFloat(t / total) * w }
        if let peaks = model.peaks {
            let cols = peaks.columns(from: 0, to: total, count: max(1, Int(w)))
            let scale = CGFloat(1 / max(0.05, peaks.peak)) * (h * 0.45)
            var path = Path()
            for (i, c) in cols.enumerated() {
                path.move(to: CGPoint(x: CGFloat(i) + 0.5, y: mid - CGFloat(c.max) * scale))
                path.addLine(to: CGPoint(x: CGFloat(i) + 0.5, y: mid - CGFloat(c.min) * scale + 0.5))
            }
            context.stroke(path, with: .color(PP.inkStaff.opacity(0.7)), lineWidth: 1)
        }
        if let track = model.draft {
            context.fill(Path(CGRect(x: 0, y: 0, width: x(track.trimStart), height: h)), with: .color(PP.inkStaff.opacity(0.35)))
            let e = x(track.playEnd)
            context.fill(Path(CGRect(x: e, y: 0, width: w - e, height: h)), with: .color(PP.inkStaff.opacity(0.35)))
            context.fill(Path(CGRect(x: x(track.bar1Seconds) - 1, y: 0, width: 2, height: h)), with: .color(PP.accent))
        }
        let window = CGRect(x: x(model.viewStart), y: 1, width: max(3, x(model.viewSpan)), height: h - 2)
        context.stroke(Path(roundedRect: window, cornerRadius: 2), with: .color(PP.accent), lineWidth: 1.5)
        if let p = model.playhead {
            context.fill(Path(CGRect(x: x(p) - 0.5, y: 0, width: 1, height: h)), with: .color(PP.success))
        }
    }
}
#endif
