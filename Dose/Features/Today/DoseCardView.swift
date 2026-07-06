import SwiftUI

/// A single dose card for the Today screen. Layout (name-leading):
///
///   [ icon ] Name                 08:00
///            dosage              [ Take ] [ ⋯ ]
///   ⓘ instruction (full width, far-left)
///   ● status pill (full width, far-left)
///
/// The icon + name lead the top row (the name is the primary element), with the dosage stacked under the
/// name. The small time sits at the top-right (red when overdue/missed, gray otherwise), with the Take/⋯
/// controls directly below it. The instruction and status pill span the full card width from the far-left
/// edge, sharing one leading edge with each other. The name stays fully readable (wraps to two lines /
/// scales, never clipping to "Aspi"). A short instruction shows in full on one line, a too-long one
/// collapses to a compact "ⓘ Instructions" indicator (the full text is on the detail screen). At
/// accessibility text sizes the card reflows to a single vertical column.
///
/// Tapping the card opens the medicine detail; the Take/Undo control and the ⋯ menu capture their own
/// taps. A settled dose (taken/skipped) shows an **Undo** control so an accidental action is reversible.
struct DoseCardView: View {
    let dose: TodayDose
    var iconName: String? = nil
    var colorHex: String? = nil
    var instructions: String? = nil
    var onTake: () -> Void
    var onUndo: () -> Void
    var onEdit: () -> Void
    var onArchive: () -> Void
    var onDelete: () -> Void
    var onOpenDetail: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var accent: Color { DoseTheme.color(for: dose.status) }
    private var settled: Bool { DoseTheme.isSettled(dose.status) }
    private var trimmedInstructions: String? {
        guard let t = instructions?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
    /// At accessibility sizes the four-column row can't give the name enough width, so reflow to a
    /// vertical layout where the name and Take each get the full card width.
    private var isAccessibilitySize: Bool { typeSize >= .accessibility1 }

    var body: some View {
        layout
            .doseCard(verticalPadding: 12)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(settled ? accent.opacity(0.10) : .clear)
            )
            // Tapping the card (anywhere except the Take/Undo and ⋯ buttons, which capture their own
            // taps) opens the medicine detail. Keeps the name a plain, queryable label.
            .contentShape(Rectangle())
            .onTapGesture { onOpenDetail() }
            .contextMenu { managementButtons }     // long-press remains a shortcut to the same actions
            .animation(.snappy, value: dose.status)
    }

    @ViewBuilder private var layout: some View {
        if isAccessibilitySize {
            // Reflowed for large accessibility text: time + ⋯ on top, the full-width name/text below,
            // then a full-width Take — nothing is squeezed into a narrow column.
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    iconBadge
                    timeText
                    Spacer(minLength: 0)
                    menuButton
                }
                nameAndDosage
                instructionAndStatus
                trailingControl
                    .frame(maxWidth: .infinity)
            }
        } else {
            // Name-leading. The whole left content (icon + name/dose, then the instruction + status) is one
            // column starting at the card's far-left edge; the time + Take/⋯ `rightColumn` is a SIBLING of
            // that column. Because the right column no longer sits ABOVE the instruction in the stack, it
            // can't push the instruction down — the instruction falls tight (~5pt) under the dose, still at
            // the far-left edge (the column's leading), bounded by the right column so it can't run under
            // the Take. The icon, name's first line, and time all share one baseline (`.firstTextBaseline`).
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        iconBadge
                        nameAndDosage
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    instructionAndStatus
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                rightColumn
            }
        }
    }

    /// Name + dosage. The name is the priority element: it wraps to two lines and only ever scales
    /// slightly (never below 75%) to stay fully readable — it must never clip to "Aspi".
    private var nameAndDosage: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(dose.medicineName)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
            if let dosage = dose.dosage, !dosage.isEmpty {
                Text(dosage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Instruction (when present) + the status pill, stacked below the controls so they get the full
    /// width of the right area. A short instruction shows in full on ONE line; a long one that wouldn't
    /// fit collapses to a compact, fixed "Instructions" indicator instead of wrapping a paragraph into
    /// the card (which would blow up this glance surface). `ViewThatFits` picks the full-text row only
    /// when its single-line ideal width fits the available width — a true line-fit test, not a character
    /// count, so it's correct across devices and text sizes. Either branch is exactly one line, so the
    /// card height is identical whether the instruction is short or long; an absent instruction simply
    /// drops the row (no empty gap). The full text is always on the detail screen (a tap away).
    private var instructionAndStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let instructions = trimmedInstructions {
                ViewThatFits(in: .horizontal) {
                    instructionRow(instructions)     // the real instruction, one line — chosen iff it fits
                    instructionRow("Instructions")   // compact indicator — fallback when it would wrap
                }
            }
            StatusChip(status: dose.status, snoozedUntil: dose.snoozedUntil)
                // Expose the chip container so a UI test can assert its leading edge matches the
                // instruction row's (one shared edge); the inner label stays queryable via `.contain`.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("statusChip")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One-line instruction row: the info icon + a single line of text — either the instruction itself
    /// or the fixed "Instructions" indicator. `lineLimit(1)` makes its ideal width the full single-line
    /// width, which is exactly what `ViewThatFits` compares against the available width to decide whether
    /// the real text fits or must collapse to the indicator. Tapping it (via the card) opens the detail.
    private func instructionRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "info.circle")
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        // Expose the row container so a UI test can measure its leading edge (the inner Text stays
        // queryable thanks to `.contain`).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("instructionRow")
    }

    /// Small fixed-size icon badge tinted with the medicine's colour (defaults applied when unset). The
    /// 30pt circle has no text baseline, so in the `.firstTextBaseline` top row it would otherwise drop to
    /// its bottom edge; pin a point just below its centre to the baseline so it optically centres on the
    /// name's/time's first line.
    private var iconBadge: some View {
        Image(systemName: MedAppearance.icon(iconName))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(MedAppearance.color(colorHex), in: Circle())
            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
            .accessibilityHidden(true)
    }

    /// The scheduled time — a small top-right timestamp (no longer the big left-hand number). Red when the
    /// dose is overdue (`.due`/`.missed` — the time has come or passed and needs attention), neutral gray
    /// otherwise. Scales with Dynamic Type.
    private var timeText: some View {
        Text(dose.scheduledFor, format: .dateTime.hour().minute())
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(timeColor)
            .accessibilityLabel(Text(dose.scheduledFor, format: .dateTime.hour().minute()))
            .accessibilityIdentifier("doseTime")
    }

    /// Red when overdue/missed (the urgent states), neutral gray otherwise.
    private var timeColor: Color {
        (dose.status == .due || dose.status == .missed) ? .red : .secondary
    }

    /// Top-right stack: the small time on top, the Take/⋯ controls below it. The time aligns to the name's
    /// first line (the enclosing top row is `.firstTextBaseline`); the Take sits directly beneath it.
    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 6) {
            timeText
            controlColumn
        }
    }

    /// The trailing control column: Take + ⋯ as one fixed-width unit so the buttons never drift and the
    /// text column can rely on the remaining space.
    private var controlColumn: some View {
        HStack(alignment: .top, spacing: 4) {
            trailingControl
            menuButton
        }
        .fixedSize()
    }

    /// Compact control: Take when unsettled, Undo when already taken/skipped. A minimum width keeps the
    /// buttons uniform across cards, while horizontal padding lets the label grow with Dynamic Type so
    /// "Take" is never clipped to "T…".
    @ViewBuilder private var trailingControl: some View {
        if settled {
            Button(action: onUndo) {
                VStack(spacing: 2) {
                    Image(systemName: DoseTheme.icon(for: dose.status)).font(.subheadline.weight(.bold))
                    Text("Undo").font(.caption2.weight(.bold)).lineLimit(1)
                }
                .frame(minWidth: 56)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo \(DoseTheme.label(for: dose.status)) for \(dose.medicineName)")
        } else {
            Button(action: onTake) {
                Text("Take")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .frame(minWidth: 56)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .background(.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Take \(dose.medicineName)")
        }
    }

    /// Discoverable "⋯" entry to the management menu (Edit / Archive / Delete permanently).
    private var menuButton: some View {
        Menu {
            managementButtons
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More options for \(dose.medicineName)")
    }

    @ViewBuilder private var managementButtons: some View {
        Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
        Button(action: onArchive) { Label("Archive", systemImage: "archivebox") }
        Button(role: .destructive, action: onDelete) {
            Label("Delete permanently", systemImage: "trash")
        }
    }
}
