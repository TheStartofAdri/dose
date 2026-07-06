import Foundation
import SwiftData
@preconcurrency import UserNotifications

/// Handles notification actions (Take / Snooze / Skip, plus a default tap). Each action appends a
/// `DoseLog` and cancels the slot's pending escalation. This is the OS-level half of Execution Mode,
/// so it stays fast and asks no questions.
@MainActor
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        super.init()
    }

    // Show reminders as banners even while the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let idString = info["medicineID"] as? String, let medicineID = UUID(uuidString: idString) else { return }
        let name = info["medicineName"] as? String ?? "Medicine"
        let dosage = info["dosage"] as? String
        let scheduledFor = Self.resolveScheduledFor(info: info, now: .now)
        handleAction(response.actionIdentifier, medicineID: medicineID, name: name, dosage: dosage,
                     scheduledFor: scheduledFor)
    }

    /// The action half, extracted so it's directly testable (a `UNNotificationResponse` can't be
    /// constructed in tests). Writes the `DoseLog` to the OBSERVED main context — not a detached
    /// `ModelContext(container)` — so a skip/take from a notification is reflected live by the
    /// History/Today `@Query` without a reload. Returns the written log (for tests to assert which
    /// context it belongs to).
    @discardableResult
    func handleAction(_ actionID: String, medicineID: UUID, name: String, dosage: String?,
                      scheduledFor: Date) -> DoseLog? {
        switch actionID {
        case NotificationScheduler.takeAction, UNNotificationDefaultActionIdentifier:
            let log = log(.taken, medicineID: medicineID, name: name, dosage: dosage, scheduledFor: scheduledFor)
            NotificationScheduler.shared.cancelSlot(medicineID: medicineID, scheduledFor: scheduledFor)
            return log

        case NotificationScheduler.skipAction:
            let log = log(.skipped, medicineID: medicineID, name: name, dosage: dosage, scheduledFor: scheduledFor)
            NotificationScheduler.shared.cancelSlot(medicineID: medicineID, scheduledFor: scheduledFor)
            return log

        case NotificationScheduler.snoozeAction:
            let log = log(.snoozed, medicineID: medicineID, name: name, dosage: dosage, scheduledFor: scheduledFor)
            NotificationScheduler.shared.cancelSlot(medicineID: medicineID, scheduledFor: scheduledFor)
            NotificationScheduler.shared.scheduleSnooze(medicineID: medicineID, medicineName: name,
                                                        dosage: dosage, scheduledFor: scheduledFor)
            return log

        default:
            return nil
        }
    }

    @discardableResult
    private func log(_ action: DoseAction, medicineID: UUID, name: String, dosage: String?, scheduledFor: Date) -> DoseLog {
        // Write to the OBSERVED main context (not a detached `ModelContext(container)`), so a skip/take
        // taken from a notification is reflected live by the History/Today @Query without a reload.
        DoseActionWriter.record(action, medicineID: medicineID, medicineName: name, dosage: dosage,
                                scheduledFor: scheduledFor, into: container.mainContext)
    }

    /// Escalations carry an exact `scheduledFor`; repeating base reminders carry only hour/minute,
    /// so we resolve the most recent occurrence at/just before `now`.
    static func resolveScheduledFor(info: [AnyHashable: Any], now: Date, calendar: Calendar = .current) -> Date {
        if let epoch = info["scheduledFor"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(epoch))
        }
        let hour = info["hour"] as? Int ?? calendar.component(.hour, from: now)
        let minute = info["minute"] as? Int ?? calendar.component(.minute, from: now)
        let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        return candidate > now ? calendar.date(byAdding: .day, value: -1, to: candidate) ?? candidate : candidate
    }
}
