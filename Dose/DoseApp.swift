import SwiftUI
import SwiftData
import UserNotifications

@main
struct DoseApp: App {
    let container: ModelContainer
    let notificationHandler: NotificationActionHandler

    init() {
        #if DEBUG
        // Drop a real OLD-schema store on disk first, so makeContainer() below exercises the genuine
        // upgrade path (used by the sim "install over an existing store" check). V1 = the oldest
        // shape; V2 = the previously-shipped shape an actual on-device store is at today.
        if CommandLine.arguments.contains("-installLegacyStore") {
            DoseStore.writeLegacyStoreForTesting()
        }
        if CommandLine.arguments.contains("-installLegacyStoreV2") {
            DoseStore.writeLegacyStoreV2ForTesting()
        }
        #endif
        // Non-fatal: runs the migration plan and recovers gracefully instead of crashing on a
        // failed/legacy-store migration (was a force-crash at this line for existing users).
        container = DoseStore.makeContainer()
        // Surface a store-recovery (empty list after a failed load) instead of silently continuing.
        StoreHealth.shared.seedFromRealLoad(DoseStore.lastLoadOutcome)
        notificationHandler = NotificationActionHandler(container: container)
        UNUserNotificationCenter.current().delegate = notificationHandler
        NotificationScheduler.shared.registerCategories()

        // Background refill of windowed reminders. register(...) MUST run before launch completes
        // (here) and requires the task id in BGTaskSchedulerPermittedIdentifiers, or it traps.
        BackgroundRefresh.register(container: container)
        BackgroundRefresh.scheduleNext()

        #if DEBUG
        // UI tests launch with `-skipAuth` (and never a real StoreKit session), so grant premium for the
        // test run: it lifts the trial-gated entry paywall and unlocks the gated features so the existing
        // UI tests reach the app and the premium surfaces. `-premium` forces it explicitly.
        if CommandLine.arguments.contains("-skipAuth") || CommandLine.arguments.contains("-premium") {
            SubscriptionStore.shared.setPremiumForTesting(true)
            // The AI UI tests expect to reach Review directly, so pre-grant the one-time AI consent —
            // otherwise the consent prompt would intercept the first parse.
            AIConsent.grant()
        }
        // Lets the consent UI test exercise the first-run prompt even with `-skipAuth` (which premium-grants).
        if CommandLine.arguments.contains("-resetAIConsent") {
            AIConsent.revoke()
        }
        if CommandLine.arguments.contains("-uiTestReset") {
            let context = container.mainContext
            try? context.delete(model: DoseLog.self)
            try? context.delete(model: DoseTime.self)
            try? context.delete(model: Medicine.self)
            try? context.delete(model: Note.self)
            try? context.save()
        }
        if CommandLine.arguments.contains("-seedHistoryDemo") {
            let context = container.mainContext
            try? context.delete(model: DoseLog.self)
            try? context.delete(model: DoseTime.self)
            try? context.delete(model: Medicine.self)
            try? context.delete(model: Note.self)
            DebugSeed.seedHistoryDemo(into: context)
        }
        if CommandLine.arguments.contains("-seedCardLayoutDemo") {
            let context = container.mainContext
            try? context.delete(model: DoseLog.self)
            try? context.delete(model: DoseTime.self)
            try? context.delete(model: Medicine.self)
            try? context.delete(model: Note.self)
            DebugSeed.seedCardLayoutDemo(into: context)
        }
        if CommandLine.arguments.contains("-seedTimeColorDemo") {
            let context = container.mainContext
            try? context.delete(model: DoseLog.self)
            try? context.delete(model: DoseTime.self)
            try? context.delete(model: Medicine.self)
            try? context.delete(model: Note.self)
            DebugSeed.seedTimeColorDemo(into: context)
        }
        if CommandLine.arguments.contains("-seedWeekDemo") {
            let context = container.mainContext
            try? context.delete(model: DoseLog.self)
            try? context.delete(model: DoseTime.self)
            try? context.delete(model: Medicine.self)
            try? context.delete(model: Note.self)
            DebugSeed.seedWeekDemo(into: context)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
