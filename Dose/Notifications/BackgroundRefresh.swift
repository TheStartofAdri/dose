import Foundation
import SwiftData
import BackgroundTasks
import os

/// Keeps the *windowed* reminders (every-N-days, bounded courses, escalations) topped up while the
/// app is closed. Those are one-shots within `NotificationPlanner.defaultWindow`; without this they'd
/// only be refilled when the user opens the app, so a finite course goes silent after the window.
///
/// A `BGAppRefreshTask` periodically re-runs the scheduler to extend the horizon. iOS schedules this
/// at its OWN discretion (best-effort, not guaranteed, and gated by the user's Background App Refresh
/// setting) — it narrows the gap dramatically but does not eliminate it; durable daily/weekly/monthly
/// reminders remain the guaranteed path. Registration must happen before launch completes (DoseApp.init);
/// `BGTaskScheduler.register` traps if the identifier isn't in `BGTaskSchedulerPermittedIdentifiers`.
enum BackgroundRefresh {
    static let taskID = "com.thestartofadri.dose.refresh"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.thestartofadri.dose",
                                       category: "background")
    private static var container: ModelContainer?

    /// Register the handler once, in DoseApp.init.
    static func register(container: ModelContainer) {
        self.container = container
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            handle(task)
        }
    }

    /// Ask iOS for the next refresh (~12h out is a floor, not a promise). Safe to call repeatedly;
    /// on the simulator `submit` throws `.unavailable`, which we log rather than crash on.
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Failed to submit background refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(_ task: BGTask) {
        scheduleNext()   // always re-arm the next one first
        let work = Task { @MainActor in
            let escalationEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.escalationEnabled)
            let meds = (try? container?.mainContext.fetch(FetchDescriptor<Medicine>())) ?? []
            let logs = (try? container?.mainContext.fetch(FetchDescriptor<DoseLog>())) ?? []
            let appts = (try? container?.mainContext.fetch(FetchDescriptor<Appointment>())) ?? []
            NotificationScheduler.shared.reschedule(medicines: meds, logs: logs, appointments: appts,
                                                    escalationEnabled: escalationEnabled)
            // Wait for the async notification adds to flush before telling iOS we're done — otherwise the
            // app can be suspended mid-enqueue and drop the refilled reminders (N2).
            await NotificationScheduler.shared.pendingRequestsSettled()
            // SINGLE completion point — always runs and ends the task exactly once (no double-completion
            // race). `success` reflects whether the deadline cut us short: the expiration handler only
            // cancels, so on expiry this reports success:false, satisfying the BGTask contract (A5).
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
