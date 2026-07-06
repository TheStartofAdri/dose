import Foundation
import SwiftData

/// The one place drafts become confirmed `Medicine`s and notifications get (re)scheduled.
/// Nothing reaches Execution Mode without passing through here.
@MainActor
enum MedicineWriter {
    /// Confirm one or more new drafts → persisted, confirmed medicines + their dose-time rules.
    /// Returns the created medicines so callers (e.g. the manual post-save extras step) can keep working
    /// with the just-saved object.
    @discardableResult
    static func confirm(_ drafts: [EditableDraft], context: ModelContext, escalationEnabled: Bool) -> [Medicine] {
        var created: [Medicine] = []
        for draft in drafts {
            let medicine = Medicine(name: draft.trimmedName, trustState: .confirmed)
            let doseTimes = draft.doseTimes()
            draft.apply(to: medicine, newDoseTimes: doseTimes)
            context.insert(medicine)
            for doseTime in doseTimes { context.insert(doseTime) }
            created.append(medicine)
        }
        persist(context: context, escalationEnabled: escalationEnabled)
        return created
    }

    /// Apply an edit to an existing medicine, replacing its dose-time rules.
    static func saveEdit(_ medicine: Medicine, draft: EditableDraft, context: ModelContext, escalationEnabled: Bool) {
        for old in medicine.doseTimes { context.delete(old) }
        let doseTimes = draft.doseTimes()
        draft.apply(to: medicine, newDoseTimes: doseTimes)
        for doseTime in doseTimes { context.insert(doseTime) }
        persist(context: context, escalationEnabled: escalationEnabled)
    }

    /// Archive (`archived == true` → `isActive = false`) or unarchive (`false` → `isActive = true`) a
    /// medicine, then reschedule. Unarchiving re-arms the medicine's reminders (it now passes
    /// `Medicine.activeConfirmed`, so `persist`'s reschedule plans its on-time reminders again) — not a
    /// silent flag flip. The single place archive state changes, shared by Today, the detail view, and
    /// the Archived list.
    static func setArchived(_ medicine: Medicine, _ archived: Bool, context: ModelContext, escalationEnabled: Bool) {
        medicine.isActive = !archived
        persist(context: context, escalationEnabled: escalationEnabled)
    }

    /// Permanently remove a medicine and its `DoseTime` rules (cascade). `DoseLog` history has no
    /// relationship to `Medicine`, so past dose records are intentionally kept.
    static func deletePermanently(_ medicine: Medicine, context: ModelContext, escalationEnabled: Bool) {
        context.delete(medicine)
        persist(context: context, escalationEnabled: escalationEnabled)
    }

    private static func persist(context: ModelContext, escalationEnabled: Bool) {
        try? context.save()
        let all = (try? context.fetch(FetchDescriptor<Medicine>())) ?? []
        let allLogs = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        NotificationScheduler.shared.reschedule(medicines: all, logs: allLogs, escalationEnabled: escalationEnabled)
    }
}
