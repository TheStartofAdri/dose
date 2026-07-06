import SwiftUI
import SwiftData

/// The safety gate. Nothing enters Execution Mode until the user confirms here. Every field is
/// explicitly labeled; confidence/uncertainty is visible per field; low confidence on name/dosage
/// forces an edit before Confirm.
struct ReviewConfirmView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismissFlow) private var dismissFlow
    @AppStorage(SettingsKeys.escalationEnabled) private var escalationEnabled = false

    @State var drafts: [EditableDraft]
    var onRetake: (() -> Void)? = nil

    @State private var extrasMedicine: Medicine?

    private var blocked: Bool { drafts.contains { $0.blocksConfirm } }

    var body: some View {
        Form {
            ForEach(Array(drafts.enumerated()), id: \.element.id) { index, draft in
                Section {
                    DraftDetailFields(draft: draft)
                } header: {
                    Text(drafts.count > 1 ? "Medicine \(index + 1)" : "Details")
                } footer: {
                    confidenceFooter(for: draft)
                }
                DraftScheduleEditor(draft: draft)
            }
        }
        .navigationTitle(drafts.count > 1 ? "Review \(drafts.count) medicines" : "Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onRetake {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Retake", systemImage: "camera") { onRetake() }
                }
            }
        }
        // After a single-medicine confirm, offer the same optional extras step the manual path uses.
        .navigationDestination(isPresented: extrasBinding) {
            if let medicine = extrasMedicine { PostSaveExtrasView(medicine: medicine) }
        }
        .safeAreaInset(edge: .bottom) { confirmBar }
    }

    private var extrasBinding: Binding<Bool> {
        Binding(get: { extrasMedicine != nil }, set: { if !$0 { extrasMedicine = nil } })
    }

    private func confirm() {
        let created = MedicineWriter.confirm(drafts, context: context, escalationEnabled: escalationEnabled)
        // One new medicine → route into the post-save extras step (icon / duration / instructions).
        // Zero or several → just finish (multi-med extras would be ambiguous; editable later via Edit).
        if created.count == 1, let medicine = created.first {
            extrasMedicine = medicine
        } else {
            dismissFlow()
        }
    }

    @ViewBuilder
    private func confidenceFooter(for draft: EditableDraft) -> some View {
        if draft.source != .manual {
            switch draft.confidence {
            case .low:
                Label("Low confidence — please verify the highlighted fields", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            case .medium:
                Label("Please double-check the highlighted fields", systemImage: "questionmark.circle")
                    .foregroundStyle(.orange)
            case .high:
                EmptyView()
            }
        }
    }

    private var confirmBar: some View {
        VStack(spacing: 6) {
            if blocked {
                Text("Review the highlighted fields, then confirm — edit them, or tap “Looks right” if they're correct.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: confirm) {
                Text(drafts.count > 1 ? "Confirm all" : "Confirm")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(blocked)
        }
        .padding()
        .background(.bar)
    }
}
