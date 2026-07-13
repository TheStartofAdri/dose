import Foundation
import SwiftData

/// Undo a recorded Take/Skip for one dose occurrence: delete its log(s), then re-plan so a still-future
/// slot gets back the one-shot reminder that the take/skip had cancelled. Reuses the single `reschedule`
/// path — which never schedules a past occurrence (`occ >= now`) and is a full replace, so it's
/// idempotent (a later re-take cancels the slot again). The counterpart to `DoseActionWriter.record`.
@MainActor
enum DoseUndo {
    /// Deletes the slot's log(s) and reschedules. Returns how many logs were removed (0 = nothing to
    /// undo → no reschedule). `scheduler`/`now` are injectable for tests.
    @discardableResult
    static func undo(medicineID: UUID, scheduledFor: Date, context: ModelContext, escalationEnabled: Bool,
                     scheduler: NotificationScheduler? = nil, now: Date = .now) -> Int {
        // Resolve `.shared` inside the @MainActor body rather than as a default argument (a nonisolated
        // context, which warns under Swift 6). Callers/tests can still inject a scheduler.
        let scheduler = scheduler ?? .shared
        let toDelete = ((try? context.fetch(FetchDescriptor<DoseLog>())) ?? []).filter {
            $0.medicineID == medicineID && ExecutionEngine.sameSlot($0.scheduledFor, scheduledFor)
        }
        guard !toDelete.isEmpty else { return 0 }
        for log in toDelete { context.delete(log) }
        try? context.save()
        // Re-plan from the post-deletion state (the slot is unactioned again). Fetch fresh — a caller's
        // @Query hasn't observed the delete yet within this synchronous call.
        let meds = (try? context.fetch(FetchDescriptor<Medicine>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        scheduler.reschedule(medicines: meds, logs: logs, escalationEnabled: escalationEnabled, now: now)
        return toDelete.count
    }
}
