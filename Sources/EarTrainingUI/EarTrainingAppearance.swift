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
#endif
