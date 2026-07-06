import SwiftUI
import SwiftData

/// Progressive disclosure: after a manual save, offer the optional extras (icon/colour, treatment
/// length, instructions) as a skippable follow-up so the primary add form stays simple. Operates on
/// the just-created medicine; "Save details" applies via the normal edit path, "Skip" leaves the
/// medicine as saved.
struct PostSaveExtrasView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismissFlow) private var dismissFlow
    @AppStorage(SettingsKeys.escalationEnabled) private var escalationEnabled = false

    let medicine: Medicine
    @State private var draft: EditableDraft

    init(medicine: Medicine) {
        self.medicine = medicine
        _draft = State(initialValue: EditableDraft(editing: medicine))
    }

    var body: some View {
        Form {
            Section {
                Label("\(medicine.name) is saved.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Add optional details, or skip — you can change these anytime from the medicine's page.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            MedicineExtrasEditor(draft: draft)
        }
        .navigationTitle("Almost done")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip") { dismissFlow() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text("Save details").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("saveExtras")
            .padding()
            .background(.bar)
        }
    }

    private func save() {
        MedicineWriter.saveEdit(medicine, draft: draft, context: context, escalationEnabled: escalationEnabled)
        dismissFlow()
    }
}
