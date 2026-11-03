#if canImport(SwiftUI)
import SwiftUI

/// The host supplies its design tokens without making this feature depend on the app target.
public struct EarTrainingAppearance {
    public var accent: Color
    public var ink: Color
    public var cardSurface: Color
    public var background: Color
    public var displayFont: Font
    public var titleFont: Font
    public var embedded: Bool

    public init(accent: Color = .indigo, ink: Color = .primary,
                cardSurface: Color = .primary.opacity(0.035), background: Color = .primary.opacity(0.025),
                displayFont: Font = .system(size: 32, weight: .bold, design: .rounded),
                titleFont: Font = .title2.bold(), embedded: Bool = false) {
        self.accent = accent; self.ink = ink; self.cardSurface = cardSurface; self.background = background
        self.displayFont = displayFont; self.titleFont = titleFont; self.embedded = embedded
    }
}

/// A button's weight: the one action to take, or one beside it.
public enum EarButtonRole { case primary, secondary }

/// The host's button styles, so embedded screens match it. Without them (the standalone ear
/// trainer) buttons keep the system's bordered look.
public struct EarButtonStyles {
    public var primary: (AnyView) -> AnyView
    public var secondary: (AnyView) -> AnyView

    public init(primary: @escaping (AnyView) -> AnyView, secondary: @escaping (AnyView) -> AnyView) {
        self.primary = primary; self.secondary = secondary
    }
}

private struct EarButtonStylesKey: EnvironmentKey {
    static let defaultValue: EarButtonStyles? = nil
}

extension EnvironmentValues {
    public var earButtonStyles: EarButtonStyles? {
        get { self[EarButtonStylesKey.self] }
        set { self[EarButtonStylesKey.self] = newValue }
    }
}

private struct EarButtonModifier: ViewModifier {
    let role: EarButtonRole
    @Environment(\.earButtonStyles) private var styles

    func body(content: Content) -> some View {
        if let styles {
            (role == .primary ? styles.primary : styles.secondary)(AnyView(content))
        } else if role == .primary {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func earButton(_ role: EarButtonRole) -> some View { modifier(EarButtonModifier(role: role)) }
}
#endif
