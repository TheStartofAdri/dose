import SwiftUI

/// A single metric tile — a big number over a caption (the mock's Taken / Skipped / Snoozed / Total
/// row). Fills its width so a row of tiles distributes evenly.
struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = DoseColors.neutral

    var body: some View {
        VStack(spacing: DoseSpacing.xs) {
            Text(value).font(DoseFont.statNumber).foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Circular adherence ring with the percentage in the centre. `rate` is 0...1; `nil` renders a "—"
/// placeholder (no data). Ring colour follows the same thresholds the rate tiles use.
struct AdherenceRing: View {
    let rate: Double?
    var size: CGFloat = 76
    var lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            Circle().stroke(DoseColors.neutral.opacity(0.15), lineWidth: lineWidth)
            if let rate {
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, rate)))
                    .stroke(ringColor(rate), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((rate * 100).rounded()))%")
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
            } else {
                Text("—")
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private func ringColor(_ rate: Double) -> Color {
        switch rate {
        case ..<0.5: DoseColors.missed
        case ..<0.8: DoseColors.due
        default:     DoseColors.taken
        }
    }
}
