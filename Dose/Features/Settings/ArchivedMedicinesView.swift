import SwiftUI
import SwiftData

/// The one place archived medicines are visible (reached from Settings). Each can be **Unarchived**
/// (restored to Today/History/This week/report, with its reminders re-armed via the scheduler) or
/// **Deleted permanently**. The two actions are deliberately distinct so they can't be confused.
struct ArchivedMedicinesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Medicine.name) private var medicines: [Medicine]
    @AppStorage(SettingsKeys.escalationEnabled) private var escalationEnabled = false

    @State private var deleting: Medicine?

    private var archived: [Medicine] { Medicine.archived(medicines) }

    var body: some View {
        Group {
            if archived.isEmpty {
                // Never a broken empty screen — also covers unarchiving/deleting the last one in place.
                VStack {
                    Spacer()
                    DoseEmptyState(icon: "archivebox",
                                   title: "No archived medicines",
                                   message: "Medicines you archive appear here, where you can restore or delete them.")
                    Spacer()
                }
            } else {
                List {
                    ForEach(archived) { med in
                        row(med)
                    }
                }
            }
        }
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete permanently?", isPresented: deleteBinding, presenting: deleting) { med in
            Button("Delete \(med.name)", role: .destructive) { delete(med) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Removes the medicine and its schedule. Past dose history is still kept for your records.")
        }
    }

    private func row(_ med: Medicine) -> some View {
        HStack(spacing: 12) {
            MedicineIconBadge(iconName: med.iconName, colorHex: med.colorHex, size: 34)   // match the other entity rows
            VStack(alignment: .leading, spacing: 1) {
                Text(med.name).font(.headline)
                if let dosage = med.dosage, !dosage.isEmpty {
                    Text(dosage).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Menu {
                Button { unarchive(med) } label: { Label("Unarchive", systemImage: "tray.and.arrow.up") }
                Button(role: .destructive) { deleting = med } label: {
                    Label("Delete permanently", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Manage \(med.name)")
        }
        .accessibilityIdentifier("archivedRow.\(med.name)")
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    /// Restore the medicine — `setArchived(false)` flips it active AND reschedules, re-arming its reminders.
    private func unarchive(_ med: Medicine) {
        MedicineWriter.setArchived(med, false, context: context, escalationEnabled: escalationEnabled)
    }

    private func delete(_ med: Medicine) {
        // Clear the stored reference BEFORE deleting (matches TodayView's "B1" guard): the delete's save
        // re-fires the `medicines` @Query, and the `.confirmationDialog(presenting: deleting)` actions/
        // message read `med.name` — reading an invalidated @Model there is a SwiftData fatal error.
        deleting = nil
        MedicineWriter.deletePermanently(med, context: context, escalationEnabled: escalationEnabled)
    }
}
