import SwiftUI

/// The Today "Next up" hero — the single soonest un-acted dose, with a prominent Take and a 10-minute
/// Snooze. Sits above the full day's timeline; the caller shows it only when a next dose exists.
///
/// The informational text is a SINGLE combined accessibility element, so the hero's medicine name is
/// not a separate static text that would collide with the same dose's schedule row in UI queries. The
/// Take/Snooze buttons carry DISTINCT labels ("Take … now" / "Snooze …") from the per-row Take, and
/// tapping the card body (not the buttons) opens the medicine detail, mirroring the rows.
struct NextUpCard: View {
    let dose: TodayDose
    var onTake: () -> Void
    var onSnooze: () -> Void
    var onOpenDetail: () -> Void

    private var overdue: Bool { dose.status == .due || dose.status == .missed }

    var body: some View {
        VStack(alignment: .leading, spacing: DoseSpacing.md) {
            VStack(alignment: .leading, spacing: DoseSpacing.md) {
                HStack(spacing: DoseSpacing.sm) {
                    Text("NEXT UP")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DoseColors.accent)
                    Text(dose.scheduledFor, format: .dateTime.hour().minute())
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(overdue ? DoseColors.missed : .secondary)
                    Spacer(minLength: 0)
                    if overdue {
                        Label("Overdue", systemImage: "exclamationmark.circle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(DoseColors.missed)
                            .labelStyle(.titleAndIcon)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(dose.medicineName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    if let dosage = dose.dosage, !dosage.isEmpty {
                        Text(dosage).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            // One element → its label ("Next up: …") never collides with the schedule row's plain name.
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)

            HStack(spacing: DoseSpacing.sm) {
                Button(action: onTake) {
                    Text("Take")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DoseSpacing.md)
                        .background(DoseColors.accent, in: RoundedRectangle(cornerRadius: DoseRadius.control, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take \(dose.medicineName) now")

                Button(action: onSnooze) {
                    Text("Snooze")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, DoseSpacing.lg)
                        .padding(.vertical, DoseSpacing.md)
                        .background(DoseColors.neutral.opacity(0.14), in: RoundedRectangle(cornerRadius: DoseRadius.control, style: .continuous))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Snooze \(dose.medicineName)")
            }
        }
        .doseCardStyle()
        // Tap the card body (the buttons capture their own taps) → medicine detail, like the rows.
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenDetail)
    }

    private var accessibilityLabel: String {
        let time = dose.scheduledFor.formatted(date: .omitted, time: .shortened)
        let dosage = dose.dosage.map { ", \($0)" } ?? ""
        return "Next up: \(dose.medicineName)\(dosage), at \(time)"
    }
}
