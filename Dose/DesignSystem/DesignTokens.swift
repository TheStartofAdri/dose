import SwiftUI
import UIKit

/// Design tokens for the v1.0 redesign. ONE source for spacing, radii, type, and the status/brand
/// palette, so every screen restyle stays consistent and no view hardcodes a hex or a magic number.
/// Purely additive — nothing here changes an existing screen until that screen adopts it.

// MARK: - Spacing (4-pt rhythm)

enum DoseSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

// MARK: - Corner radii

enum DoseRadius {
    static let card: CGFloat = 22       // matches the existing doseCard() so cards don't shift
    static let control: CGFloat = 16
    static let tile: CGFloat = 16
    static let chip: CGFloat = 11
    static let small: CGFloat = 8
}

// MARK: - Typography (semantic; Dynamic-Type friendly)

enum DoseFont {
    static let screenTitle = Font.largeTitle.bold()
    static let sectionTitle = Font.title3.weight(.semibold)
    static let cardTitle = Font.headline
    static let statNumber = Font.system(size: 26, weight: .bold, design: .rounded)
    static let chip = Font.subheadline.weight(.semibold)
}

// MARK: - Palette (single source for status + brand colours)

enum DoseColors {
    /// App accent — resolves to the `AccentColor` asset (blue) in both light and dark.
    static let accent = Color.accentColor

    // Status palette — the ONE source. `DoseTheme`, the History chart, and the PDF renderer all read
    // these, so a status can never render as two different colours across screens again.
    static let taken   = Color.green
    static let due      = Color.orange
    static let missed  = Color.red
    static let snoozed = Color.blue
    /// Neutral for status text / chips (upcoming, skipped).
    static let neutral = Color.secondary
    /// Solid neutral for chart/graph fills — deliberately more visible than `neutral`.
    static let neutralSolid = Color(uiColor: .systemGray)

    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)

    /// UIKit mirror for the on-device PDF renderer (which draws in UIKit, not SwiftUI).
    enum UI {
        static let taken = UIColor.systemGreen
        static let due = UIColor.systemOrange
        static let missed = UIColor.systemRed
        static let neutralSolid = UIColor.systemGray
        static let none = UIColor.systemGray5
    }
}

// MARK: - Elevation / card style

extension View {
    /// Soft shadow used by the redesigned solid cards (distinct from the frosted `doseCard()`).
    func doseElevation() -> some View {
        shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    /// Redesigned solid card (mock style): opaque grouped background, rounded, softly elevated.
    /// Additive — screens adopt it during their restyle phase; the frosted `doseCard()` stays until then.
    func doseCardStyle(padding: CGFloat = DoseSpacing.lg) -> some View {
        self.padding(padding)
            .background(DoseColors.cardBackground,
                        in: RoundedRectangle(cornerRadius: DoseRadius.card, style: .continuous))
            .doseElevation()
    }
}
