import SwiftUI

/// A selectable pill filter — History's All / Taken / Skipped / Snoozed / Missed chips.
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DoseFont.chip)
                .padding(.horizontal, DoseSpacing.md)
                .padding(.vertical, DoseSpacing.sm)
                .background(isSelected ? AnyShapeStyle(DoseColors.accent)
                                       : AnyShapeStyle(DoseColors.neutral.opacity(0.14)),
                            in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// A section header — a title with an optional trailing accessory (e.g. a "See all" button).
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(DoseFont.sectionTitle)
            Spacer()
            trailing()
        }
    }
}

/// A standard empty state (icon + title + message + optional action), so empty screens read alike.
struct DoseEmptyState<Action: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder var action: () -> Action

    init(icon: String, title: String, message: String,
         @ViewBuilder action: @escaping () -> Action = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action
    }

    var body: some View {
        VStack(spacing: DoseSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(DoseColors.neutral)
            Text(title).font(.headline)
            Text(message)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            action()
        }
        .frame(maxWidth: .infinity)
        .padding(DoseSpacing.xl)
    }
}
