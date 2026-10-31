#if os(macOS)
import AppKit
import SwiftUI

/// A primary button that fills up and presses itself when full. Used where the learner has
/// just succeeded and there's one sensible next step (see `AutoAdvance`).
///
/// - Hovering pauses it (a pause icon shows); clicking or Return goes at once.
/// - Reduce Motion: no fill, a seconds count instead.
/// - VoiceOver: never presses itself; it's an ordinary button.
/// - A disabled button doesn't count down.
/// Give it an `.id` that changes with what it continues to, so a new step starts a new count.
struct TimedContinueButton: View {
    let title: String
    let seconds: Double
    var height: CGFloat = PP.Size.targetMin
    let action: () -> Void

    @StateObject private var countdown = Countdown()
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var counts: Bool { isEnabled && seconds > 0 && !NSWorkspace.shared.isVoiceOverEnabled }

    var body: some View {
        Button {
            countdown.fire()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if counts && !countdown.fired {
                    if hovering {
                        Image(systemName: "pause.fill").font(.system(size: 11, weight: .bold)).opacity(0.85)
                    } else if reduceMotion {
                        Text("\(max(1, Int((seconds - countdown.elapsed).rounded(.up))))")
                            .monospacedDigit().opacity(0.85)
                    }
                }
            }
        }
        .buttonStyle(PPTimedButtonStyle(fill: counts && !reduceMotion ? min(1, countdown.elapsed / seconds) : 1,
                                        height: height))
        .keyboardShortcut(.defaultAction)
        .onHover { inside in
            hovering = inside
            countdown.paused = inside
        }
        .onAppear {
            countdown.duration = seconds
            countdown.onFire = action
            if counts { countdown.start() }
        }
        .onDisappear { countdown.stop() }
        .onChange(of: isEnabled) { enabled in
            if enabled && counts { countdown.start() } else { countdown.stop() }
        }
        .accessibilityHint(counts ? "Continues by itself in a few seconds. Hover to pause." : "")
    }
}

/// The count behind `TimedContinueButton`: its own main-run-loop timer, so it keeps time
/// however often the screen around it redraws (the mic level, the playhead).
final class Countdown: ObservableObject {
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var fired = false
    var duration: Double = 3
    var paused = false
    var onFire: (() -> Void)?
    private var timer: Timer?
    private var lastTick: Date?

    func start() {
        guard timer == nil, !fired else { return }
        lastTick = Date()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func fire() {
        guard !fired else { return }
        fired = true
        stop()
        onFire?()
    }

    private func tick() {
        let now = Date()
        defer { lastTick = now }
        guard !paused, let last = lastTick else { return }
        // A stalled run loop (a sheet, a slow frame) doesn't jump the count.
        elapsed += min(0.1, now.timeIntervalSince(last))
        if elapsed >= duration { fire() }
    }

    deinit { timer?.invalidate() }
}

/// The primary button look, with the accent filling from the left as the count runs.
struct PPTimedButtonStyle: ButtonStyle {
    /// 0–1: how full. 1 looks exactly like `PPPrimaryButtonStyle`.
    var fill: Double
    var height: CGFloat = PP.Size.targetMin
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ppButton)
            .foregroundColor(PP.onAccent)
            .padding(.horizontal, PP.Space.s8)
            .frame(minHeight: height)
            .background(
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(PP.accent.opacity(0.55))
                        Rectangle().fill(PP.accent).frame(width: geo.size.width * CGFloat(fill))
                    }
                }
                .clipShape(Capsule())
            )
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
#endif
