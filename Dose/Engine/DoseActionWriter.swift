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

    @discardableResult
    static func record(
        _ action: DoseAction,
        medicineID: UUID,
        medicineName: String,
        dosage: String?,
        scheduledFor: Date,
        into context: ModelContext
    ) -> DoseLog {
        let log = DoseLog(medicineID: medicineID, medicineName: medicineName, dosage: dosage,
                          scheduledFor: scheduledFor, action: action)
        context.insert(log)
        // Capture (don't swallow) the error: this runs on the lock-screen/background action path where
        // a silent failure would mean a tapped Take/Skip never persisted, invisibly.
        do {
            try context.save()
        } catch {
            logger.error("Failed to persist \(action.rawValue, privacy: .public) for \(medicineName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return log
    }
}
