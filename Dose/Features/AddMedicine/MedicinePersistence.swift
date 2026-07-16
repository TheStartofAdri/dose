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
        let oldRules = medicine.snapshot().rules
        for old in medicine.doseTimes { context.delete(old) }
        let doseTimes = draft.doseTimes()
        draft.apply(to: medicine, newDoseTimes: doseTimes)
        for doseTime in doseTimes { context.insert(doseTime) }
        // Stamp only when the dose-time RULES actually changed (not a name-only edit, and not a no-op toggle
        // like "all seven weekdays" ↔ "every day"), so adherence/streak stop reconstructing past misses from
        // the NEW schedule. A real schedule change otherwise injects phantom misses on past days and breaks
        // the streak; a SPURIOUS stamp silently wipes genuine past misses.
        if isScheduleChange(from: oldRules, to: medicine.snapshot().rules) { medicine.scheduleChangedAt = .now }
        persist(context: context, escalationEnabled: escalationEnabled)
    }

    /// Whether replacing `old` dose rules with `new` is a REAL schedule change (i.e. should stamp
    /// `scheduleChangedAt`). Compares each rule's canonical scheduling identity, not its raw fields, so a
    /// behaviorally-identical edit — e.g. "all seven weekdays" ↔ "every day" — is correctly seen as no change.
    nonisolated static func isScheduleChange(from old: [DoseSlotRule], to new: [DoseSlotRule]) -> Bool {
        Set(old.map(scheduleKey)) != Set(new.map(scheduleKey))
    }

    /// Canonical scheduling identity of a dose rule: two rules with the same key fire on exactly the same
    /// days at the same time. Mirrors the repeat precedence in `DoseSlotRule.applies` (days-of-month →
    /// every-N-days → specific weekdays → every day): precedence-shadowed fields are dropped, weekdays are
    /// set-normalized (order/dupes don't matter), and "all seven weekdays" collapses to "every day" — the
    /// exact toggle that was spuriously stamping.
    nonisolated private static func scheduleKey(_ rule: DoseSlotRule) -> String {
        let time = "\(rule.hour):\(rule.minute)"
        if !rule.daysOfMonth.isEmpty {
            return "\(time)|dom:\(Set(rule.daysOfMonth).sorted())"
        }
        if rule.intervalDays >= 2, let anchor = rule.anchorDate {
            return "\(time)|int:\(rule.intervalDays)@\(anchor.timeIntervalSinceReferenceDate)"
        }
        let weekdays = Set(rule.weekdays)
        if !weekdays.isEmpty && weekdays != Set(1...7) {
            return "\(time)|wd:\(weekdays.sorted())"
        }
        return "\(time)|daily"   // no weekdays, or all seven → every day
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
        let appts = (try? context.fetch(FetchDescriptor<Appointment>())) ?? []
        NotificationScheduler.shared.reschedule(medicines: all, logs: allLogs, appointments: appts,
                                                escalationEnabled: escalationEnabled)
    }
}
