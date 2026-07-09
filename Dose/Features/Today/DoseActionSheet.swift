import SwiftUI

/// The dose action sheet — Taken / Skipped / Snooze for one dose, with snooze presets (10 / 30 / 60 /
/// custom). Presented as a bottom sheet from Today's "Next up" hero and the detail screen. Snooze passes
/// the chosen minutes up, which the caller writes to the DoseLog + re-arms the reminder at that interval.
///
/// Snooze is offered ONLY for a due / missed / snoozed dose — never for an `.upcoming` (not-yet-due) one:
/// snoozing a dose that isn't due yet is meaningless and would leave its original on-time reminder to
/// re-arm on the next reschedule (a duplicate reminder). Taken/Skipped are always available.
struct DoseActionSheet: View {
    let dose: TodayDose
    var onTake: () -> Void
    var onSkip: () -> Void
    var onSnooze: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showCustom = false
    @State private var customMinutes = 45

    private let presets = [10, 30, 60]
    private let customChoices = [15, 20, 45, 90, 120, 180]

    /// Snooze is meaningful only for a dose that's due/overdue/already-snoozed — not one still upcoming.
    static func offersSnooze(for status: DoseStatus) -> Bool {
        status == .due || status == .missed || status == .snoozed
    }
    private var offersSnooze: Bool { Self.offersSnooze(for: dose.status) }

    var body: some View {
        VStack(spacing: DoseSpacing.lg) {
            VStack(spacing: 2) {
                Text(dose.medicineName).font(.headline)
                Text(dose.scheduledFor.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, DoseSpacing.md)

            HStack(spacing: DoseSpacing.lg) {
                bigButton("Taken", icon: "checkmark", color: DoseColors.taken,
                          a11y: "Mark \(dose.medicineName) taken") { onTake(); dismiss() }
                bigButton("Skipped", icon: "minus", color: DoseColors.neutral,
                          a11y: "Skip \(dose.medicineName) today") { onSkip(); dismiss() }
                if offersSnooze {
                    bigButton("Snooze", icon: "clock", color: DoseColors.snoozed,
                              a11y: "Snooze \(dose.medicineName) 10 minutes") { onSnooze(10); dismiss() }
                }
            }

            if offersSnooze {
                Divider()

                VStack(alignment: .leading, spacing: DoseSpacing.sm) {
                    Text("Snooze for").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: DoseSpacing.sm) {
                        ForEach(presets, id: \.self) { minutes in
                            Button { onSnooze(minutes); dismiss() } label: {
                                Text(label(minutes))
                                    .font(DoseFont.chip)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, DoseSpacing.md)
                                    .background(DoseColors.neutral.opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: DoseRadius.control, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                    }
                    Button { withAnimation { showCustom.toggle() } } label: {
                        Label("Custom time", systemImage: "slider.horizontal.3").font(.subheadline)
                    }
                    .padding(.top, DoseSpacing.xs)

                    if showCustom {
                        HStack {
                            Picker("Minutes", selection: $customMinutes) {
                                ForEach(customChoices, id: \.self) { Text(label($0)).tag($0) }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 110)
                            Button("Snooze") { onSnooze(customMinutes); dismiss() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            Button("Cancel", role: .cancel) { dismiss() }
                .frame(maxWidth: .infinity)
                .padding(.top, DoseSpacing.xs)
        }
        .padding(DoseSpacing.lg)
        .presentationDetents([.height(showCustom ? 540 : (offersSnooze ? 380 : 240))])
        .presentationDragIndicator(.visible)
    }

    private func bigButton(_ title: String, icon: String, color: Color, a11y: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DoseSpacing.sm) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(color, in: Circle())
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
    }

    private func label(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes)m"
    }
}
