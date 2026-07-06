import Foundation
import SwiftData
import os
@preconcurrency import UserNotifications

/// Turns a `NotificationPlan` into real local notifications. EVERY reminder is now a per-occurrence
/// ONE-SHOT (on-time = a non-repeating calendar trigger at the dose's wall-clock time; escalation /
/// lead-time = time-interval one-shots), so a single slot can be cancelled when its dose is taken —
/// the fix for the on-time reminder firing for an already-taken dose (double-dose prompt). The trade:
/// reminders are windowed and refilled (by every foreground reschedule and `BackgroundRefresh`) rather
/// than an OS-guaranteed infinite repeat. All scheduling funnels through `reschedule(...)`.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()
    static let categoryID = "DOSE_REMINDER"

    // Action identifiers (shared with the action handler).
    static let takeAction = "TAKE"
    static let snoozeAction = "SNOOZE"
    static let skipAction = "SKIP"

    private let center = UNUserNotificationCenter.current()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.thestartofadri.dose",
                                       category: "notifications")
    /// Removal sink for `cancelSlot` — overridable in tests to capture cancelled ids without the live
    /// notification center. `nil` → the real center.
    var removePending: (([String]) -> Void)?
    /// Add sink for `submit` — overridable in tests to capture scheduled requests without the live
    /// notification center. `nil` → the real center.
    var addPending: ((UNNotificationRequest) -> Void)?

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Reads the current OS notification settings and publishes whether reminders are effectively off
    /// (denied/disabled), so the UI can WARN instead of the app scheduling silently into the void.
    /// Called on launch and on every foreground (RootView).
    func refreshPermissionStatus() async {
        #if DEBUG
        // Screenshot/UITest seam: force the denied banner regardless of the simulator's real state.
        if CommandLine.arguments.contains("-stubNotificationsDenied") {
            NotificationStatus.shared.remindersDisabled = true
            return
        }
        #endif
        let settings = await center.notificationSettings()
        NotificationStatus.shared.remindersDisabled = NotificationStatus.shouldWarn(for: settings.authorizationStatus)
    }

    func registerCategories() {
        // Unambiguous labels for a medication reminder (behavior unchanged).
        let take = UNNotificationAction(identifier: Self.takeAction, title: "Take", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Remind in 10 min", options: [])
        let skip = UNNotificationAction(identifier: Self.skipAction, title: "Skip today", options: [.destructive])
        let category = UNNotificationCategory(identifier: Self.categoryID,
                                              actions: [take, snooze, skip],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    /// Rebuilds the entire schedule from the current confirmed medicines and their logs. `logs` lets the
    /// planner skip doses already taken/skipped, so a refill never resurrects a reminder for a recorded
    /// dose. On-time reminders are submitted first (their slots get first claim on the 64-cap).
    func reschedule(medicines: [Medicine], logs: [DoseLog], escalationEnabled: Bool, now: Date = .now) {
        let snapshots = Medicine.activeConfirmed(medicines).map { $0.snapshot() }
        let plan = NotificationPlanner.plan(medicines: snapshots, logs: logs.map { $0.snapshot() },
                                            now: now, escalationEnabled: escalationEnabled)
        // Surface the 64-pending cap: if the plan had to drop reminders, the UI shows a notice.
        NotificationStatus.shared.update(from: plan)

        center.removeAllPendingNotificationRequests()
        for reminder in plan.snoozes { addSnoozeRebuild(reminder, now: now) }
        for reminder in plan.onTime { addOnTime(reminder) }
        for reminder in plan.escalations { add(reminder, now: now) }
        for reminder in plan.leadTime { add(reminder, now: now) }
        if let fire = plan.sentinelFireDate { addRefillSentinel(fire: fire, now: now) }
    }

    /// The coverage-end sentinel: a plain notification — no dose category (no Take/Skip buttons) and
    /// no medicineID, so the action handler ignores it and a tap just opens the app, which is the
    /// refresh. Fires only if the user hasn't opened the app (and background refresh hasn't run)
    /// before the scheduled one-shots run out.
    private func addRefillSentinel(fire: Date, now: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Your reminders need a refresh"
        content.body = "Open Dose to keep your medication reminders coming."
        content.sound = SettingsKeys.soundEnabled_default ? .default : nil
        content.userInfo = ["kind": "refill"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fire.timeIntervalSince(now)),
                                                        repeats: false)
        submit(UNNotificationRequest(identifier: NotificationPlanner.refillSentinelID,
                                     content: content, trigger: trigger))
    }

    /// Re-arms a snooze the planner reconstructed from the log after the wipe above — same content and
    /// deterministic id as `scheduleSnooze`, but at the REMAINING interval instead of a fresh 10 min.
    private func addSnoozeRebuild(_ reminder: WindowedReminder, now: Date) {
        let interval = reminder.fireDate.timeIntervalSince(now)
        guard interval > 0 else { return }
        let content = Self.makeContent(
            name: reminder.medicineName, dosage: reminder.dosage,
            userInfo: [
                "medicineID": reminder.medicineID.uuidString,
                "medicineName": reminder.medicineName,
                "dosage": reminder.dosage as Any,
                "scheduledFor": Int(reminder.scheduledFor.timeIntervalSince1970),
                "kind": "snooze",
            ]
        )
        submit(UNNotificationRequest(identifier: reminder.id, content: content,
                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
    }

    // MARK: - Translating reminders to requests

    /// On-time dose reminder: a NON-repeating calendar trigger at the occurrence's exact wall-clock time
    /// — same delivery moment, `.timeSensitive`, category, sound and "Time for X" content as before, but
    /// cancellable per occurrence (the only behavioural change vs the old repeating trigger).
    private func addOnTime(_ reminder: WindowedReminder) {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.scheduledFor)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let content = Self.makeContent(
            name: reminder.medicineName, dosage: reminder.dosage,
            userInfo: [
                "medicineID": reminder.medicineID.uuidString,
                "medicineName": reminder.medicineName,
                "dosage": reminder.dosage as Any,
                "scheduledFor": Int(reminder.scheduledFor.timeIntervalSince1970),
                "kind": "primary",
            ]
        )
        submit(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }

    private func add(_ reminder: WindowedReminder, now: Date) {
        let interval = reminder.fireDate.timeIntervalSince(now)
        guard interval > 0 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)

        let kind = reminder.leadMinutes != nil ? "leadtime" : (reminder.isEscalation ? "escalation" : "primary")
        let content = Self.makeContent(
            name: reminder.medicineName, dosage: reminder.dosage,
            escalation: reminder.isEscalation, leadMinutes: reminder.leadMinutes,
            userInfo: [
                "medicineID": reminder.medicineID.uuidString,
                "medicineName": reminder.medicineName,
                "dosage": reminder.dosage as Any,
                "scheduledFor": Int(reminder.scheduledFor.timeIntervalSince1970),
                "kind": kind,
            ]
        )
        submit(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }

    /// Builds a dose-reminder content. `static` + `internal` so it's unit-testable under
    /// `@testable import Dose` (it depends only on statics). Every reminder is **time-sensitive** so
    /// it breaks through Focus / Do Not Disturb / Sleep — medication reminders matter at night, which
    /// is exactly when a default `.active` notification would be silenced. (Requires the standard
    /// `com.apple.developer.usernotifications.time-sensitive` entitlement; NOT `.critical`.)
    static func makeContent(name: String, dosage: String?, escalation: Bool = false,
                            leadMinutes: Int? = nil,
                            userInfo: [String: Any]) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        if let leadMinutes {
            content.title = "\(name) coming up in \(leadMinutes) min"
        } else {
            content.title = escalation ? "Still time for \(name)" : "Time for \(name)"
        }
        content.body = dosage.map { "Take \($0)" } ?? "Tap to mark as taken."
        content.sound = SettingsKeys.soundEnabled_default ? .default : nil
        content.categoryIdentifier = categoryID
        content.interruptionLevel = .timeSensitive
        content.userInfo = userInfo
        return content
    }

    /// Submit a request, logging (not swallowing) any scheduling error.
    private func submit(_ request: UNNotificationRequest) {
        if let addPending { addPending(request); return }
        let id = request.identifier
        center.add(request) { error in
            if let error {
                Self.logger.error("Failed to schedule notification \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Cancel EVERY pending reminder for one dose occurrence — on-time, escalation, AND lead-time — so a
    /// take/skip from anywhere (Today card or any notification action) stops all further prompts for that
    /// slot. This is what prevents the on-time reminder firing for an already-taken dose (double-dose).
    func cancelSlot(medicineID: UUID, scheduledFor: Date) {
        let ids = NotificationPlanner.slotIDs(medicineID, scheduledFor)
        if let removePending { removePending(ids) }
        else { center.removePendingNotificationRequests(withIdentifiers: ids) }
    }

    /// Schedules a fresh one-shot reminder `NotificationPlanner.escalationDelay` from now (Snooze), tied
    /// to the dose `scheduledFor` it postpones via a DETERMINISTIC id, so taking/skipping that dose later
    /// cancels it (`cancelSlot` → `slotIDs` includes the snooze). `scheduledFor` carries the original
    /// occurrence, so a Take from the snooze records the right dose. Still a 10-min one-shot.
    func scheduleSnooze(medicineID: UUID, medicineName: String, dosage: String?, scheduledFor: Date) {
        let content = Self.makeContent(
            name: medicineName, dosage: dosage,
            userInfo: [
                "medicineID": medicineID.uuidString,
                "medicineName": medicineName,
                "dosage": dosage as Any,
                "scheduledFor": Int(scheduledFor.timeIntervalSince1970),
                "kind": "snooze",
            ]
        )
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: NotificationPlanner.escalationDelay, repeats: false)
        submit(UNNotificationRequest(identifier: NotificationPlanner.snoozeID(medicineID, scheduledFor),
                                     content: content, trigger: trigger))
    }
}
