import SwiftUI

/// The labeled detail fields for one medicine draft — Name / Dosage / Form / Pack size, each a
/// clearly labeled row. Shared by the **manual entry** screen and the **AI/scan Review** gate so
/// both read the same labeled "Details" styling. Confidence/uncertainty notes only appear for
/// non-manual drafts (manual drafts carry none), so the same view serves both.
struct DraftDetailFields: View {
    @Bindable var draft: EditableDraft

    var body: some View {
        fieldCell(label: "Name", placeholder: "Required", text: $draft.name, key: "name")
        fieldCell(label: "Dosage", placeholder: "e.g. 500 mg", text: $draft.dosage, key: "dosage")
        fieldCell(label: "Form", placeholder: "e.g. tablet, solution", text: $draft.form, key: "form")
        // "Pack size" (not "Quantity") + caption so it's never misread as the per-dose amount.
        fieldCell(label: "Pack size", placeholder: "e.g. 100 ml", text: $draft.quantity, key: "quantity",
                  caption: "Total amount in the package — not the dose.")
    }

    /// One field + its validation note as a SINGLE row, so the warning is unambiguously bound to its
    /// field: the note sits indented directly under the field and the field itself is tinted/highlighted
    /// (red = must edit, orange = check). Manual drafts carry no must/uncertain fields → no tint, no note.
    @ViewBuilder
    private func fieldCell(label: String, placeholder: String, text: Binding<String>, key: String,
                           caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledDraftField(label: label, placeholder: placeholder, text: text, highlight: highlight(key)) {
                draft.markEdited(key)
            }
            if draft.mustReview(key) {
                // A must-review field WARNS but doesn't trap a correct value: "Looks right" confirms
                // it as-is (clears the block); editing also clears it.
                HStack(spacing: 8) {
                    Label("Please review and edit this", systemImage: "exclamationmark.circle.fill")
                        .font(.caption).foregroundStyle(.red)
                    Spacer(minLength: 8)
                    Button("Looks right") { draft.acknowledge(key) }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
                .padding(.leading, 104)   // align under the value column (92pt label + 12pt spacing)
            } else if draft.wasAcknowledged(key) {
                Label("Reviewed", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green).padding(.leading, 104)
            } else if draft.isUncertain(key) {
                Label("Unclear — please check", systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(.orange).padding(.leading, 104)
            } else if let caption {
                // Subtle clarifying hint (e.g. pack size ≠ dose). Yields to any review note above.
                Text(caption)
                    .font(.caption).foregroundStyle(.secondary).padding(.leading, 104)
            }
        }
        .listRowBackground(rowTint(key))
    }

    private func highlight(_ key: String) -> Color? {
        if draft.mustReview(key) { return .red }
        if draft.isUncertain(key) && !draft.wasAcknowledged(key) { return .orange }
        return nil
    }

    private func rowTint(_ key: String) -> Color? {
        if draft.mustReview(key) { return Color.red.opacity(0.10) }
        if draft.isUncertain(key) && !draft.wasAcknowledged(key) { return Color.orange.opacity(0.10) }
        return nil
    }
}

/// A labeled label/value row: caption label on the left, editable value on the right.
///
/// Autofill and autocorrection are disabled here on purpose. These are medicine fields, not
/// personal data — leaving iOS autofill on caused a stray suggestion (e.g. "At") to be committed
/// into the empty Name field. Disabling the content type at the single shared component fixes it
/// everywhere the fields are used (manual entry AND the Review gate).
struct LabeledDraftField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var highlight: Color? = nil       // tints the label when the field needs attention (red/orange)
    var onChange: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(highlight ?? .secondary)
                .frame(width: 92, alignment: .leading)
            TextField(placeholder, text: $text)
                .textContentType(.none)
                .autocorrectionDisabled()
                .accessibilityIdentifier(label)     // stable lookup (the visible label is a sibling Text)
                .onChange(of: text) { onChange?() }
        }
    }
}
