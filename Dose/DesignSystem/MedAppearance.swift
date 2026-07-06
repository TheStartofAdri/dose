import SwiftUI

/// The fixed icon + colour palette a user can pick for a medicine, plus sensible fallbacks. Stored
/// on `Medicine` as `iconName` (SF Symbol) and `colorHex` ("#RRGGBB"); both optional, so a medicine
/// with no choice renders the defaults. Purpose: distinguish visually-similar names at a glance.
enum MedAppearance {
    /// Selectable SF Symbols (all exist on iOS 18).
    static let icons: [String] = [
        "pills.fill", "pill.fill", "capsule.fill", "drop.fill",
        "syringe.fill", "cross.vial.fill", "bandage.fill", "heart.fill",
        "lungs.fill", "brain.head.profile", "eye.fill", "leaf.fill",
    ]

    /// Selectable colours as hex (kept as a small, legible palette).
    static let colors: [String] = [
        "#34C759", // green
        "#0A84FF", // blue
        "#5E5CE6", // indigo
        "#BF5AF2", // purple
        "#FF375F", // pink
        "#FF9F0A", // orange
        "#FFD60A", // yellow
        "#64D2FF", // teal
        "#8E8E93", // gray
    ]

    static let defaultIcon = "pills.fill"

    /// Icon to render for a (possibly nil) stored value.
    static func icon(_ name: String?) -> String {
        guard let name, icons.contains(name) else { return defaultIcon }
        return name
    }

    /// Accent colour to render for a (possibly nil) stored hex. Falls back to the app accent.
    static func color(_ hex: String?) -> Color {
        guard let hex, let color = Color(hex: hex) else { return .accentColor }
        return color
    }
}

extension Color {
    /// Parses "#RRGGBB" / "RRGGBB" (and "#RRGGBBAA"); returns nil on anything malformed.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        } else {
            r = Double((value & 0xFF000000) >> 24) / 255
            g = Double((value & 0x00FF0000) >> 16) / 255
            b = Double((value & 0x0000FF00) >> 8) / 255
            a = Double(value & 0x000000FF) / 255
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
