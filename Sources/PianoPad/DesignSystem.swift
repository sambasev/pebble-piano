#if os(macOS)
import AppKit
import SwiftUI

// PerfectPiano Expressive Glass: the app's design tokens and shared components.
// The source of truth is the "PerfectPiano Expressive Glass" design system (its tokens.json);
// keep the names and values here in step with it.
//
// Principles: one bold action per screen; glass for chrome, paper for music; shape carries
// meaning (pills are actions, squares are tools, circles are modes); mistakes are specific
// and calm, never shown by colour alone.

enum PP {
    // MARK: Colour (light, dark)

    /// Window background behind everything; gives the glass colour to refract.
    static let surface = Color.pp(0xEEEAFF, 0x15112A)
    /// Solid cards and controls that must not be see-through.
    static let surfaceRaised = Color.pp(0xFFFFFF, 0x221C3D)
    /// Fill for floating chrome (with a blur behind it).
    static let surfaceGlass = Color.pp(0xFFFFFF, 0x282048, lightAlpha: 0.62, darkAlpha: 0.62)
    /// 1 pt rim on glass panels.
    static let surfaceGlassEdge = Color.pp(0xFFFFFF, 0xFFFFFF, lightAlpha: 0.9, darkAlpha: 0.14)
    /// Primary text.
    static let ink = Color.pp(0x1B1630, 0xF2EFFF)
    /// Secondary text: labels, captions, metadata.
    static let inkMuted = Color.pp(0x4B4566, 0xB9B2D6)
    /// Staff lines, hairlines, quiet strokes. Never for text.
    static let inkStaff = Color.pp(0x9C95B8, 0x6F6890)
    /// Iris: the one primary action, progress, the next key to play.
    static let accent = Color.pp(0x5B3DF5, 0x8F7BFF)
    /// Text and icons on accent.
    static let onAccent = Color.pp(0xFFFFFF, 0x15112A)
    /// Decorative shapes and reference audition.
    static let lilac = Color.pp(0xB7A6FF, 0x4A3A9E)
    static let apricot = Color.pp(0xFFB38A, 0xB8653A)
    static let mint = Color.pp(0x7FD8C4, 0x2F8F7D)
    /// Wrong notes only. Always pair with an icon or words.
    static let mistake = Color.pp(0xC4262C, 0xFF6B6F)
    static let mistakeSoft = Color.pp(0xFFD6D7, 0x5A1F24)
    /// Bar or lesson complete. Pair with a check.
    static let success = Color.pp(0x0B6B5C, 0x4FD1B5)
    /// Cautions that are not wrong notes: replays, a missing backing track, app messages.
    static let warning = Color.pp(0x9A4A12, 0xFFB38A)
    /// Feedback chips and toasts.
    static let inverse = Color.pp(0x1B1630, 0xF2EFFF)
    static let onInverse = Color.pp(0xFFFFFF, 0x15112A)
    /// On-screen keys. White keys stay light in dark mode so the keyboard still reads as a piano.
    static let keyWhite = Color.pp(0xFFFFFF, 0xE9E5FA)
    static let keyBlack = Color.pp(0x1B1630, 0x0B0918)
    /// Labels on white keys (always dark, because the keys are always light).
    static let keyLabel = Color(hex: 0x4B4566)
    static let focusRing = Color.pp(0x5B3DF5, 0xB3A6FF)
    /// The one shadow in the system, under floating glass.
    static let glassShadow = Color.pp(0x281478, 0x000000, lightAlpha: 0.12, darkAlpha: 0.45)

    /// Sheet music. Light is white paper; dark is a dim night page with soft lavender ink,
    /// so the score isn't a floodlight in a dark room. Which one shows is set by `PaperStyle`
    /// and the window's appearance, and reaches views as `\.paper` in the environment.
    struct Paper {
        let isDark: Bool
        let page: Color
        let ink: Color
        let faint: Color
        let accent: Color
        let audition: Color
        let success: Color
        let mistake: Color
        let apricot: Color
        let warning: Color
        let shadow: Color

        static let light = Paper(
            isDark: false, page: .white, ink: .black, faint: Color(white: 0.42),
            accent: Color(hex: 0x5B3DF5), audition: Color(hex: 0x8F7BFF), success: Color(hex: 0x0B6B5C),
            mistake: Color(hex: 0xC4262C), apricot: Color(hex: 0xFFB38A), warning: Color(hex: 0x9A4A12),
            shadow: Color(hex: 0x281478, alpha: 0.14))

        static let dark = Paper(
            isDark: true, page: Color(hex: 0x1E1A33), ink: Color(hex: 0xDAD5EE), faint: Color(hex: 0x9C95B8),
            accent: Color(hex: 0xA897FF), audition: Color(hex: 0xC4B8FF), success: Color(hex: 0x4FD1B5),
            mistake: Color(hex: 0xFF6B6F), apricot: Color(hex: 0xB8653A), warning: Color(hex: 0xFFB38A),
            shadow: Color(hex: 0x000000, alpha: 0.45))
    }

    // MARK: Spacing, radius, size

    enum Space {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
        static let s12: CGFloat = 48
    }

    enum Radius {
        static let sm: CGFloat = 10
        static let key: CGFloat = 12
        static let md: CGFloat = 18
        static let lg: CGFloat = 20
        static let xl: CGFloat = 32
    }

    enum Size {
        /// Smallest target in the lesson flow (compact toolbar controls go down to `compact`).
        static let targetMin: CGFloat = 44
        /// The primary action and its neighbouring icon buttons.
        static let targetPrimary: CGFloat = 60
        /// Dense Mac toolbars: still comfortable for a pointer.
        static let compact: CGFloat = 32
        /// The on-screen keyboard, and its height in a short window.
        static let keyboard: CGFloat = 150
        static let keyboardCompact: CGFloat = 110
    }

    /// Window heights (content, in points) where the layout changes.
    enum WindowHeight {
        /// Below this the layout goes compact. At full size the Practice tab's rows (keyboard,
        /// Pebbles, toolbar) take about 600 pt, so a shorter window leaves the music under two lines.
        static let roomy: CGFloat = 860
        /// The compact layout's tightest fit. Below this the window scrolls rather than crop.
        static let floor: CGFloat = 672
    }
}

// MARK: - Type

extension Font {
    static let ppDisplay = Font.system(size: 54, weight: .heavy)
    static let ppTitle = Font.system(size: 32, weight: .bold)
    static let ppHeadline = Font.system(size: 18, weight: .semibold)
    static let ppBody = Font.system(size: 17)
    static let ppButton = Font.system(size: 18, weight: .semibold)
    static let ppCallout = Font.system(size: 15, weight: .medium)
    static let ppEyebrow = Font.system(size: 13, weight: .semibold)
    static let ppCaption = Font.system(size: 12, weight: .semibold)
}

extension Text {
    /// Uppercase label above a title.
    func ppEyebrow() -> some View {
        font(.ppEyebrow).tracking(1.2).textCase(.uppercase).foregroundColor(PP.inkMuted)
    }
}

// MARK: - Colour helpers

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// A colour that follows the window's light or dark appearance.
    static func pp(_ light: UInt32, _ dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        func ns(_ hex: UInt32, _ alpha: Double) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: CGFloat(alpha))
        }
        let lightColor = ns(light, lightAlpha), darkColor = ns(dark, darkAlpha)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
        })
    }
}

// MARK: - Surfaces

/// The window ground: the lilac surface with three soft shapes for the glass to pick up.
struct PPBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                PP.surface
                Ellipse()
                    .fill(PP.lilac)
                    .frame(width: 420, height: 380)
                    .rotationEffect(.degrees(-18))
                    .position(x: 60, y: h * 0.55)
                Circle()
                    .fill(PP.apricot)
                    .frame(width: 360, height: 360)
                    .position(x: w - 40, y: h - 60)
                RoundedRectangle(cornerRadius: 56, style: .continuous)
                    .fill(PP.mint)
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(18))
                    // Behind the report panel, never behind the header's text.
                    .position(x: w - 70, y: h * 0.42)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Floating glass: Liquid Glass on macOS 26, a tinted material before that, and a solid
/// raised surface when Reduce Transparency is on.
struct PPGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var padding: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let padded = content.padding(padding)
        if reduceTransparency {
            padded
                .background(shape.fill(PP.surfaceRaised))
                .overlay(shape.strokeBorder(PP.inkStaff.opacity(0.4), lineWidth: 1))
        } else {
            glass(padded, shape: shape)
        }
    }

    @ViewBuilder
    private func glass<V: View>(_ view: V, shape: RoundedRectangle) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            view.glassEffect(.regular, in: shape)
        } else {
            materialGlass(view, shape: shape)
        }
        #else
        materialGlass(view, shape: shape)
        #endif
    }

    private func materialGlass<V: View>(_ view: V, shape: RoundedRectangle) -> some View {
        view
            .background(shape.fill(PP.surfaceGlass))
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(PP.surfaceGlassEdge, lineWidth: 1))
            .shadow(color: PP.glassShadow, radius: 15, x: 0, y: 10)
    }
}

extension View {
    /// Floating chrome: toolbars, the lesson panel, the keyboard tray.
    func ppGlass(cornerRadius: CGFloat = PP.Radius.xl, padding: CGFloat = PP.Space.s6) -> some View {
        modifier(PPGlassModifier(cornerRadius: cornerRadius, padding: padding))
    }

    /// Paper for sheet music (white, or the night page): notation never sits on glass.
    func ppPaper(cornerRadius: CGFloat = PP.Radius.sm) -> some View {
        modifier(PPPaperModifier(cornerRadius: cornerRadius))
    }

    /// Puts the sheet-music palette for the saved `PaperStyle` and this window's appearance
    /// into the environment. Apply once, at the window's root.
    func ppPaperStyle() -> some View {
        modifier(PPPaperStyleModifier())
    }
}

// MARK: - Sheet-music paper

/// How sheet music is shown. Saved per user.
enum PaperStyle: String, CaseIterable, Identifiable {
    case matchAppearance, light, dark
    static let storageKey = "paperStyle"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .matchAppearance: return "Match appearance"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

private struct PaperKey: EnvironmentKey {
    static let defaultValue = PP.Paper.light
}

extension EnvironmentValues {
    /// The sheet-music palette in use.
    var paper: PP.Paper {
        get { self[PaperKey.self] }
        set { self[PaperKey.self] = newValue }
    }
}

private struct CompactKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True in a short window (a small laptop in full screen): the keyboard and gaps shrink.
    var ppCompact: Bool {
        get { self[CompactKey.self] }
        set { self[CompactKey.self] = newValue }
    }
}

/// Fits the app to the window's height. A short window gets the compact layout; one too short
/// even for that (full screen on a small display, or a display set to larger text) scrolls,
/// so the tabs at the top and the controls at the bottom are never cut off.
struct PPWindowFit<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            if height >= PP.WindowHeight.floor {
                content
                    .environment(\.ppCompact, height < PP.WindowHeight.roomy)
                    .frame(width: geo.size.width, height: height)
            } else {
                ScrollView(.vertical) {
                    content
                        .environment(\.ppCompact, true)
                        .frame(width: geo.size.width, height: PP.WindowHeight.floor)
                }
            }
        }
    }
}

struct PPPaperStyleModifier: ViewModifier {
    @AppStorage(PaperStyle.storageKey) private var style = PaperStyle.matchAppearance
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let dark: Bool
        switch style {
        case .matchAppearance: dark = colorScheme == .dark
        case .light: dark = false
        case .dark: dark = true
        }
        return content.environment(\.paper, dark ? .dark : .light)
    }
}

struct PPPaperModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.paper) private var paper

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(paper.page)
            .clipShape(shape)
            // The night page needs a faint rim to stand off the dark window.
            .overlay(paper.isDark ? shape.strokeBorder(PP.surfaceGlassEdge, lineWidth: 1) : nil)
            .shadow(color: paper.shadow, radius: 12, x: 0, y: 6)
    }
}

// MARK: - Buttons

extension View {
    /// Buttons and toggles that don't pick a style get the glass pill and the glass checkbox.
    /// Set on the window, and again on each sheet and popover, which don't inherit it.
    func ppDefaultButtons() -> some View {
        buttonStyle(PPGlassButtonStyle()).toggleStyle(PPCheckboxToggleStyle())
    }
}

/// The one bold action per screen: an iris pill. 60 pt in the lesson flow, `compact` in toolbars.
struct PPPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = PP.Size.targetPrimary
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let large = height >= PP.Size.targetMin
        configuration.label
            .font(large ? .ppButton : .system(size: 13, weight: .semibold))
            .foregroundColor(PP.onAccent)
            .padding(.horizontal, large ? PP.Space.s8 : PP.Space.s4)
            .frame(minHeight: height)
            .background(Capsule().fill(PP.accent))
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A quieter action beside the primary: a glass pill with ink text.
struct PPGlassButtonStyle: ButtonStyle {
    var height: CGFloat = PP.Size.compact
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let large = height >= PP.Size.targetMin
        configuration.label
            .font(large ? .ppButton : .system(size: 13, weight: .medium))
            .foregroundColor(PP.ink)
            .padding(.horizontal, large ? PP.Space.s6 : PP.Space.s3)
            .frame(minHeight: height)
            .background(Capsule().fill(configuration.isPressed ? PP.surfaceRaised : PP.surfaceGlass))
            .overlay(Capsule().strokeBorder(PP.inkStaff.opacity(0.45), lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Icon-only buttons. Square = a one-shot tool; circle = a mode that stays on.
struct PPIconButtonStyle: ButtonStyle {
    enum Kind { case tool, mode }
    var kind: Kind = .tool
    var isOn = false
    var size: CGFloat = PP.Size.compact
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let radius = kind == .tool ? min(PP.Radius.md, size * 0.3) : size / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundColor(isOn ? PP.onAccent : PP.ink)
            .frame(width: size, height: size)
            .background(shape.fill(isOn ? PP.accent : (configuration.isPressed ? PP.surfaceRaised : PP.surfaceGlass)))
            .overlay(shape.strokeBorder(isOn ? Color.clear : PP.inkStaff.opacity(0.45), lineWidth: 1))
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A mode switch drawn as a chip: iris when on.
struct PPChipToggleStyle: ToggleStyle {
    var height: CGFloat = PP.Size.compact
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: PP.Space.s1) {
                if configuration.isOn {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                }
                configuration.label
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(configuration.isOn ? PP.onAccent : PP.ink)
            .padding(.horizontal, PP.Space.s3)
            .frame(minHeight: height)
            .background(Capsule().fill(configuration.isOn ? PP.accent : PP.surfaceGlass))
            .overlay(Capsule().strokeBorder(configuration.isOn ? Color.clear : PP.inkStaff.opacity(0.45), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

// MARK: - Controls

/// A few choices side by side: a glass track with the chosen one in iris.
struct PPSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var height: CGFloat = 28
    @Environment(\.isEnabled) private var isEnabled
    @Namespace private var namespace

    init(selection: Binding<Value>, _ options: [(Value, String)], height: CGFloat = 28) {
        _selection = selection
        self.options = options.map { (value: $0.0, label: $0.1) }
        self.height = height
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let chosen = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label)
                        .font(.system(size: 13, weight: chosen ? .semibold : .medium))
                        .lineLimit(1)
                        // Never truncated: a segment is at least as wide as its name.
                        .fixedSize()
                        .foregroundColor(chosen ? PP.onAccent : PP.ink)
                        .padding(.horizontal, PP.Space.s3)
                        .frame(maxWidth: .infinity, minHeight: height - 4)
                        .background {
                            if chosen {
                                Capsule().fill(PP.accent).matchedGeometryEffect(id: "chosen", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(PP.surfaceGlass))
        .overlay(Capsule().strokeBorder(PP.inkStaff.opacity(0.45), lineWidth: 1))
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selection)
        // A label set on the switch names the group, not each segment.
        .accessibilityElement(children: .contain)
    }
}

/// A pop-up choice as a glass pill: shows the current choice, opens a menu of the rest.
struct PPMenuPicker<Value: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Value
    /// What the pill says: the current choice's name.
    let current: String
    var height: CGFloat = PP.Size.compact
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            Picker(title, selection: $selection) { content }
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            HStack(spacing: PP.Space.s2) {
                Text(current).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(PP.inkMuted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(current)")
        }
        .menuStyle(.button)
        .buttonStyle(PPGlassButtonStyle(height: height))
        .menuIndicator(.hidden)
    }
}

/// One of a few longer choices, stacked: an iris dot marks the chosen one.
struct PPRadioList<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let chosen = option.0 == selection
                Button { selection = option.0 } label: {
                    HStack(alignment: .firstTextBaseline, spacing: PP.Space.s2) {
                        Circle()
                            .strokeBorder(chosen ? PP.accent : PP.inkStaff, lineWidth: chosen ? 5 : 1.5)
                            .background(Circle().fill(chosen ? PP.onAccent : PP.surfaceGlass))
                            .frame(width: 16, height: 16)
                            .alignmentGuide(.firstTextBaseline) { $0.height * 0.78 }
                        Text(option.1)
                            .foregroundColor(PP.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Minus and plus in a glass capsule.
struct PPStepper<V: Strideable>: View {
    @Binding var value: V
    let range: ClosedRange<V>
    var step: V.Stride
    @Environment(\.isEnabled) private var isEnabled

    init(value: Binding<V>, in range: ClosedRange<V>, step: V.Stride) {
        _value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        HStack(spacing: 0) {
            button("minus", "Decrease", value > range.lowerBound) { value = max(range.lowerBound, value.advanced(by: -step)) }
            Rectangle().fill(PP.inkStaff.opacity(0.45)).frame(width: 1, height: 14)
            button("plus", "Increase", value < range.upperBound) { value = min(range.upperBound, value.advanced(by: step)) }
        }
        .frame(height: 26)
        .background(Capsule().fill(PP.surfaceGlass))
        .overlay(Capsule().strokeBorder(PP.inkStaff.opacity(0.45), lineWidth: 1))
        .opacity(isEnabled ? 1 : 0.4)
        .fixedSize()
    }

    private func button(_ symbol: String, _ label: String, _ enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(PP.ink)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

extension PPStepper where V: BinaryInteger, V.Stride: BinaryInteger {
    init(value: Binding<V>, in range: ClosedRange<V>) { self.init(value: value, in: range, step: 1) }
}

/// A checkbox: a glass square, iris with a tick when on.
struct PPCheckboxToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return Button { configuration.isOn.toggle() } label: {
            HStack(spacing: PP.Space.s2) {
                ZStack {
                    shape.fill(configuration.isOn ? PP.accent : PP.surfaceGlass)
                    shape.strokeBorder(configuration.isOn ? Color.clear : PP.inkStaff, lineWidth: 1.5)
                    if configuration.isOn {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundColor(PP.onAccent)
                    }
                }
                .frame(width: 16, height: 16)
                configuration.label.foregroundColor(PP.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

/// An on/off switch: a glass track, iris when on.
struct PPSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: PP.Space.s2) {
                configuration.label.foregroundColor(PP.ink)
                Spacer(minLength: 0)
                Capsule()
                    .fill(configuration.isOn ? PP.accent : PP.surfaceGlass)
                    .overlay(Capsule().strokeBorder(configuration.isOn ? Color.clear : PP.inkStaff.opacity(0.6), lineWidth: 1))
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(configuration.isOn ? PP.onAccent : PP.ink.opacity(0.85)).padding(3)
                    }
                    .frame(width: 36, height: 20)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

/// A slider: an iris fill along a glass track, with a round thumb.
struct PPSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width, thumb: CGFloat = 16
            let fraction = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound)
                / max(.ulpOfOne, range.upperBound - range.lowerBound)
            let x = thumb / 2 + (width - thumb) * fraction
            ZStack(alignment: .leading) {
                Capsule().fill(PP.surfaceGlass)
                    .overlay(Capsule().strokeBorder(PP.inkStaff.opacity(0.45), lineWidth: 1))
                    .frame(height: 6)
                Capsule().fill(PP.accent).frame(width: x, height: 6)
                Circle().fill(PP.keyWhite)
                    .overlay(Circle().strokeBorder(PP.accent, lineWidth: 2))
                    .shadow(color: PP.glassShadow, radius: 2, y: 1)
                    .frame(width: thumb, height: thumb)
                    .offset(x: x - thumb / 2)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let f = Double(min(max(0, (g.location.x - thumb / 2) / max(1, width - thumb)), 1))
                set(range.lowerBound + f * (range.upperBound - range.lowerBound))
            })
        }
        .frame(height: 20)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement()
        .accessibilityValue("\(Int(value.rounded()))")
        .accessibilityAdjustableAction { direction in
            let by = step > 0 ? step : (range.upperBound - range.lowerBound) / 20
            set(value + (direction == .increment ? by : -by))
        }
    }

    private func set(_ v: Double) {
        var v = min(max(v, range.lowerBound), range.upperBound)
        if step > 0 { v = range.lowerBound + ((v - range.lowerBound) / step).rounded() * step }
        if v != value { value = v }
    }
}

/// A row in a glass list: iris tint when selected, a glass wash on hover. Click selects it.
struct PPSelectableRow<Content: View>: View {
    let selected: Bool
    let select: () -> Void
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PP.Radius.sm, style: .continuous)
        content
            .padding(.horizontal, PP.Space.s2)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(selected ? PP.accent.opacity(0.22) : hovering ? PP.surfaceGlass : .clear))
            .overlay(shape.strokeBorder(selected ? PP.accent.opacity(0.6) : .clear, lineWidth: 1))
            .contentShape(shape)
            .onTapGesture(perform: select)
            .onHover { hovering = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction(named: "Select", select)
    }
}

/// A text field on glass: a rounded glass box, iris rim while typing.
struct PPFieldModifier: ViewModifier {
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PP.Radius.sm, style: .continuous)
        return content
            .textFieldStyle(.plain)
            .focused($focused)
            .padding(.horizontal, PP.Space.s2 + 2)
            .padding(.vertical, 6)
            .background(shape.fill(PP.surfaceGlass))
            .overlay(shape.strokeBorder(focused ? PP.focusRing : PP.inkStaff.opacity(0.45), lineWidth: focused ? 2 : 1)
                .allowsHitTesting(false))
            .ppClickToFocus($focused)
    }
}

enum PPFocus {
    /// Focuses a field even when its focus state is stale: selecting text elsewhere (a chat reply)
    /// takes the keyboard without clearing it, and setting true again would then do nothing.
    static func refocus(_ focused: FocusState<Bool>.Binding) {
        focused.wrappedValue = false
        DispatchQueue.main.async { focused.wrappedValue = true }
    }

}

/// Over a text box: while nothing is being typed, a click anywhere in the box focuses its field.
/// The box is taller than its line of text, and selecting text elsewhere (a chat reply) leaves
/// SwiftUI thinking the field still has focus, so it ignores a click on the field; either way the
/// keys would go to the piano. While typing, clicks pass through, so the caret can still be placed.
private struct PPClickToFocus: NSViewRepresentable {
    let focus: () -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView(focus: focus) }
    func updateNSView(_ view: CatcherView, context: Context) { view.focus = focus }

    final class CatcherView: NSView {
        var focus: () -> Void
        init(focus: @escaping () -> Void) { self.focus = focus; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let typing = (window?.firstResponder as? NSTextView)?.isEditable ?? false
            return typing ? nil : super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            // Take the keyboard back from whatever holds it (selected text), then focus the field.
            window?.makeFirstResponder(nil)
            focus()
        }
    }
}

extension View {
    func ppClickToFocus(_ focused: FocusState<Bool>.Binding) -> some View {
        overlay(PPClickToFocus { PPFocus.refocus(focused) })
    }
}

extension View {
    func ppField() -> some View { modifier(PPFieldModifier()) }
}

// MARK: - Feedback

/// One specific sentence about what just happened, with an icon tile for its kind.
struct PPFeedbackChip: View {
    enum Kind { case mistake, success, hint, warning }
    let kind: Kind
    let text: String
    /// Lines the text may wrap to; 1 keeps it a single-line pill.
    var lines: Int = 1

    private var tile: (Color, Color, String) {
        switch kind {
        case .mistake: return (PP.mistake, PP.onAccent, "xmark")
        case .success: return (PP.success, PP.onAccent, "checkmark")
        case .hint: return (PP.accent, PP.onAccent, "lightbulb")
        case .warning: return (PP.apricot, Color(hex: 0x1B1630), "arrow.counterclockwise")
        }
    }

    var body: some View {
        let (fill, iconInk, symbol) = tile
        HStack(spacing: PP.Space.s2) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(iconInk)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
                .accessibilityHidden(true)
            Text(text)
                .font(.ppCallout)
                .foregroundColor(PP.onInverse)
                .lineLimit(lines)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: lines > 1)
        }
        .padding(.leading, 5)
        .padding(.trailing, PP.Space.s4)
        .padding(.vertical, 5)
        // A capsule on one line (radius = half its 36 pt height), a rounded box when wrapped.
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(PP.inverse))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shapes

/// A rectangle with only its bottom corners rounded: piano keys.
struct PPKeyShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
#endif
