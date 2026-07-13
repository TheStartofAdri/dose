import Foundation
import SwiftData
import os

/// The single place a `DoseLog` is written for a Take/Skip/Snooze action. Both UI paths (the Today
/// card/swipe and the notification action) go through here so the behaviour is identical and testable.
///
/// IMPORTANT: callers pass the **observed** context (the app's `mainContext`, which SwiftUI's
/// `@Query` reads). Writing to a *detached* `ModelContext(container)` persists to the store but does
/// not update the live `@Query`, so History/Today wouldn't reflect the action until a reload — the
/// cross-context bug this seam exists to prevent.
@MainActor
enum DoseActionWriter {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.thestartofadri.dose",
                                       category: "actions")

    #if DEBUG
    /// Test seam: force the next `save()` to fail so the failure path (no cancel, error surfaced) is
    /// deterministically exercisable. Never compiled into Release.
    static var forceSaveFailureForTesting = false
    #endif

    /// Persist the action. **Throws** on a save failure instead of swallowing it — a failed persist must
    /// never read as success, because the callers cancel the slot's reminder and show success only when
    /// this returns normally. On failure the just-inserted (unsaved) log is removed so no phantom row
    /// lingers in the observed context, and the error propagates for the caller to surface.
    @discardableResult
    static func record(
        _ action: DoseAction,
        medicineID: UUID,
        medicineName: String,
        dosage: String?,
        scheduledFor: Date,
        snoozeMinutes: Int? = nil,
        into context: ModelContext
    ) throws -> DoseLog {
        let log = DoseLog(medicineID: medicineID, medicineName: medicineName, dosage: dosage,
                          scheduledFor: scheduledFor, action: action, snoozeMinutes: snoozeMinutes)
        context.insert(log)
        do {
            #if DEBUG
            if forceSaveFailureForTesting { throw CocoaError(.coreData) }
            #endif
            try context.save()
        } catch {
            context.delete(log)   // don't leave an unsaved phantom the @Query could briefly show
            // Correlate by ID, never by name: a medication name is health data, and `.public` would
            // write it unredacted into the unified log (readable in Console.app / sysdiagnoses).
            logger.error("Failed to persist \(action.rawValue, privacy: .public) for medicine \(medicineID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
        return log
    }
}
