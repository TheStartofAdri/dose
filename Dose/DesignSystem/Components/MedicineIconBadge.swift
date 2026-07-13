import SwiftUI

/// A medicine's SF Symbol as a WHITE glyph on a solid colour circle — the ONE badge for every surface
/// (Today card, Week row, Medicine detail, archived list, report picker), so it reads identically
/// everywhere and a size change happens in one place. Colour/icon resolve through `MedAppearance`.
struct MedicineIconBadge: View {
    let iconName: String?
    let colorHex: String?
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: MedAppearance.icon(iconName))
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(MedAppearance.color(colorHex), in: Circle())
            .accessibilityHidden(true)
    }
}
