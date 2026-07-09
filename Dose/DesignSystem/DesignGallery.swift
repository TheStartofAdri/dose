#if DEBUG
import SwiftUI

/// A one-screen gallery of the redesign's tokens + components, reviewable in Xcode Previews without
/// wiring a real screen. DEBUG-only; never shipped. Update this when a token or component changes so
/// there's always a single place to eyeball the design system in light and dark.
struct DesignGallery: View {
    private let statuses: [DoseStatus] = [.upcoming, .due, .missed, .taken, .skipped, .snoozed]
    @State private var filter = "Taken"
    private let filters = ["All", "Taken", "Skipped", "Snoozed", "Missed"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DoseSpacing.xxl) {
                group("Status chips") {
                    FlowRow { ForEach(statuses, id: \.self) { StatusChip(status: $0) } }
                }

                group("Filter chips") {
                    FlowRow {
                        ForEach(filters, id: \.self) { f in
                            FilterChip(title: f, isSelected: filter == f) { filter = f }
                        }
                    }
                }

                group("Adherence ring") {
                    HStack(spacing: DoseSpacing.xl) {
                        AdherenceRing(rate: 0.87)
                        AdherenceRing(rate: 0.62)
                        AdherenceRing(rate: 0.30)
                        AdherenceRing(rate: nil)
                    }
                }

                group("Stat tiles") {
                    HStack {
                        StatTile(value: "46", label: "Taken", tint: DoseColors.taken)
                        StatTile(value: "6", label: "Skipped")
                        StatTile(value: "2", label: "Snoozed", tint: DoseColors.snoozed)
                        StatTile(value: "54", label: "Total")
                    }
                    .doseCardStyle()
                }

                group("Medicine badges") {
                    HStack(spacing: DoseSpacing.md) {
                        MedicineIconBadge(iconName: "pills.fill", colorHex: "#0A84FF")
                        MedicineIconBadge(iconName: "drop.fill", colorHex: "#34C759")
                        MedicineIconBadge(iconName: "heart.fill", colorHex: "#FF375F")
                        MedicineIconBadge(iconName: nil, colorHex: nil)
                    }
                }

                group("Empty state") {
                    DoseEmptyState(icon: "tray", title: "Nothing here yet",
                                   message: "This is the shared empty-state component.") {
                        Button("Primary action") {}.buttonStyle(.borderedProminent)
                    }
                    .doseCardStyle()
                }
            }
            .padding(DoseSpacing.lg)
        }
        .background(DoseColors.groupedBackground)
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DoseSpacing.md) {
            SectionHeader(title)
            content()
        }
    }
}

/// Minimal wrapping HStack for the gallery (keeps chips from clipping off-screen).
private struct FlowRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: DoseSpacing.sm) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Design system — light") { DesignGallery() }
#Preview("Design system — dark") { DesignGallery().preferredColorScheme(.dark) }
#endif
