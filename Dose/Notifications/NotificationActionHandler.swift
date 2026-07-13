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
        handleAction(response.actionIdentifier, kind: info["kind"] as? String,
                     medicineID: medicineID, name: name, dosage: dosage, scheduledFor: scheduledFor)
    }

    /// The action half, extracted so it's directly testable (a `UNNotificationResponse` can't be
    /// constructed in tests). Writes the `DoseLog` to the OBSERVED main context — not a detached
    /// `ModelContext(container)` — so a skip/take from a notification is reflected live by the
    /// History/Today `@Query` without a reload. Returns the written log (for tests to assert which
    /// context it belongs to).
    /// Kinds whose DEFAULT tap records the dose as taken — real dose prompts only. Informational
    /// kinds (the "coming up in N min" lead-time heads-up, future sentinels) are excluded: their
    /// `scheduledFor` is a dose that isn't due yet, so a glance-tap must be pure navigation. `nil`
    /// (a legacy payload without a kind) is treated as a dose prompt to preserve behavior.
    private static func isDosePrompt(_ kind: String?) -> Bool {
        guard let kind else { return true }
        return ["primary", "escalation", "snooze"].contains(kind)
    }

    @discardableResult
    func handleAction(_ actionID: String, kind: String? = nil, medicineID: UUID, name: String,
                      dosage: String?, scheduledFor: Date) -> DoseLog? {
        switch actionID {
        // Informational banners: the default tap just opens the app — no log, no cancellation. The
        // EXPLICIT Take/Skip buttons below still work everywhere (a deliberate early take is the
        // user's call); only the ambiguous tap is neutered.
        case UNNotificationDefaultActionIdentifier where !Self.isDosePrompt(kind):
            return nil

        // A heads-up no longer offers Snooze (its lead-time category omits the action), because a
        // heads-up snooze has no `.snoozed` log and so is silently destroyed by the next reschedule
        // (N1) — and the real on-time reminder is already scheduled. Defensive no-op for any legacy
        // heads-up still delivered with the old button.
        case NotificationScheduler.snoozeAction where !Self.isDosePrompt(kind):
            return nil

        // Each branch cancels the slot only AFTER the log persisted: if the save failed, `log(...)`
        // returns nil and we leave the pending reminder/escalation intact so the dose is re-prompted
        // rather than silently lost (C2).
        case NotificationScheduler.takeAction, UNNotificationDefaultActionIdentifier:
            guard let log = log(.taken, medicineID: medicineID, name: name, dosage: dosage, scheduledFor: scheduledFor)
            else { return nil }
            NotificationScheduler.shared.cancelSlot(medicineID: medicineID, scheduledFor: scheduledFor)
            return log

        case NotificationScheduler.skipAction:
            guard let log = log(.skipped, medicineID: medicineID, name: name, dosage: dosage, scheduledFor: scheduledFor)
            else { return nil }
            NotificationScheduler.shared.cancelSlot(medicineID: medicineID, scheduledFor: scheduledFor)
            return log

        case NotificationScheduler.snoozeAction:
            guard let log = log(.snoozed, medicineID: medicineID, name: name, dosage: dosage, scheduledFor: scheduledFor)
            else { return nil }
            NotificationScheduler.shared.cancelSlot(medicineID: medicineID, scheduledFor: scheduledFor)
            NotificationScheduler.shared.scheduleSnooze(medicineID: medicineID, medicineName: name,
                                                        dosage: dosage, scheduledFor: scheduledFor)
            return log

        default:
            return nil
        }
    }

    @discardableResult
    private func log(_ action: DoseAction, medicineID: UUID, name: String, dosage: String?, scheduledFor: Date) -> DoseLog? {
        // Write to the OBSERVED main context (not a detached `ModelContext(container)`), so a skip/take
        // taken from a notification is reflected live by the History/Today @Query without a reload.
        // `try?` — a save failure returns nil so the caller keeps the reminder instead of cancelling it.
        try? DoseActionWriter.record(action, medicineID: medicineID, medicineName: name, dosage: dosage,
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
