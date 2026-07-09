import SwiftUI

/// A medicine's SF Symbol on a tinted circle. Extracted from five inline copies (Today card, Week
/// row, Medicine detail, archived list, extras editor) so the badge reads identically everywhere and
/// a size change happens in one place. Colour/icon resolve through `MedAppearance` (with fallbacks).
struct MedicineIconBadge: View {
    let iconName: String?
    let colorHex: String?
    var size: CGFloat = 40

    var body: some View {
        let color = MedAppearance.color(colorHex)
        Image(systemName: MedAppearance.icon(iconName))
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: Circle())
    }
}
