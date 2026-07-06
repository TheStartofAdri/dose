import SwiftUI

/// A small pill showing the dose's derived status (with the snoozed-until time when relevant).
struct StatusChip: View {
    let status: DoseStatus
    var snoozedUntil: Date?

    var body: some View {
        // An explicit icon+text row (not `Label`) with the whole pill fixed-size, so the label never
        // collapses to icon-only — inside a List row a `Label` + `.fixedSize` could clip the text to ~0.
        HStack(spacing: 4) {
            Image(systemName: DoseTheme.icon(for: status))
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .foregroundStyle(DoseTheme.color(for: status))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DoseTheme.color(for: status).opacity(0.14), in: Capsule())
        .fixedSize()
    }

    private var text: String {
        if status == .snoozed, let until = snoozedUntil {
            return "Snoozed · \(until.formatted(date: .omitted, time: .shortened))"
        }
        return DoseTheme.label(for: status)
    }
}

/// Frosted "glass" card background used across the app. Padding is parameterized so dense lists
/// (the Today screen) can tighten the vertical rhythm without affecting History/Report cards.
private struct DoseCardModifier: ViewModifier {
    var verticalPadding: CGFloat = 16
    var horizontalPadding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func doseCard(verticalPadding: CGFloat = 16, horizontalPadding: CGFloat = 16) -> some View {
        modifier(DoseCardModifier(verticalPadding: verticalPadding, horizontalPadding: horizontalPadding))
    }
}
