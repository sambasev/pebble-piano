#if os(macOS)
import SwiftUI

/// A small rotary knob: drag up or down to turn it, double-click to reset.
struct KnobView: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var defaultValue: Double
    var systemImage: String? = nil
    var size: CGFloat = 26

    @State private var dragStart: Double?

    /// The knob turns through 270°, from 7:30 to 4:30.
    private var fraction: Double { (value - range.lowerBound) / (range.upperBound - range.lowerBound) }
    private var angle: Angle { .degrees(-135 + 270 * fraction) }

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().fill(PP.surfaceRaised)
                Circle().stroke(PP.inkStaff.opacity(0.6), lineWidth: 1)
                Circle()
                    .trim(from: 0, to: 0.75 * fraction)
                    .stroke(PP.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .padding(-3)
                Capsule()
                    .fill(PP.ink)
                    .frame(width: 2.5, height: size * 0.32)
                    .offset(y: -size * 0.2)
                    .rotationEffect(angle)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let start = dragStart ?? value
                        if dragStart == nil { dragStart = value }
                        // 150 points of travel covers the whole range.
                        let delta = -Double(g.translation.height) / 150 * (range.upperBound - range.lowerBound)
                        value = min(range.upperBound, max(range.lowerBound, start + delta))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onTapGesture(count: 2) { value = defaultValue }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 2) {
                    if let systemImage { Image(systemName: systemImage) }
                    Text(title)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(PP.inkMuted)
                Text("\(Int((value * 100).rounded()))%").font(.ppCaption.monospacedDigit()).foregroundColor(PP.ink)
            }
        }
        .help("\(title) volume: drag up or down, double-click to reset")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) volume")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}
#endif
