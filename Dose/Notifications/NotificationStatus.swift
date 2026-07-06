import Foundation
import Observation
import UserNotifications

/// Observable, app-wide notification health so the UI can warn the user when reminders won't actually
/// reach them — instead of the app scheduling silently into the void. Two surfaces:
///   - `remindersDisabled`: the OS permission is denied/off → nothing fires (set from
///     `getNotificationSettings` via `NotificationScheduler.refreshPermissionStatus`).
///   - `schedulingTruncated`: the schedule exceeded iOS's 64-pending cap and some reminders were
///     dropped (set from `NotificationPlan.baseTruncated` in `NotificationScheduler.reschedule`).
///
/// Read either flag in a SwiftUI `body` (e.g. `NotificationNoticeBanner`) and Observation re-renders
/// on change. The shared instance is the single source the Today and Settings banners read.
@MainActor
@Observable
final class NotificationStatus {
    static let shared = NotificationStatus()

    var remindersDisabled = false
    var schedulingTruncated = false

    /// True when there's anything worth surfacing — gate the banner on this so it takes no space
    /// (and no padding) when reminders are healthy.
    var hasNotice: Bool { remindersDisabled || schedulingTruncated }

    private init() {
        #if DEBUG
        if CommandLine.arguments.contains("-stubNotificationsDenied") { remindersDisabled = true }
        #endif
    }

    /// Mirror the plan's 64-cap truncation onto the visible flag.
    func update(from plan: NotificationPlan) {
        schedulingTruncated = plan.baseTruncated
    }

    /// Pure mapping (no main-actor state) so it's directly unit-testable: which authorization states
    /// warrant a "reminders are off" warning. Only an explicit denial means nothing will fire;
    /// `.notDetermined` is pre-prompt (we're about to ask), and provisional/ephemeral still deliver.
    nonisolated static func shouldWarn(for status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .denied: return true
        case .authorized, .provisional, .ephemeral, .notDetermined: return false
        @unknown default: return false
        }
    }
}
