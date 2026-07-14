import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var medicines: [Medicine]
    @Query private var logs: [DoseLog]
    @Query private var appointments: [Appointment]
    @AppStorage(SettingsKeys.escalationEnabled) private var escalationEnabled = false
    @AppStorage(SettingsKeys.appearance) private var appearance = "system"
    @ObservedObject private var subscription = SubscriptionStore.shared

    @State private var selectedTab = RootView.initialTab()

    /// Where cold-start routing sends the user. `.loading` until StoreKit resolves — so the main UI never
    /// renders (and never flashes) before the gate is known; `.paywall` for a brand-new user who must start
    /// the trial to enter; `.app` for everyone else (incl. a lapsed `hasEverSubscribed` user, who keeps the
    /// full core loop with only premium extras locked).
    enum EntryRoute: Equatable { case loading, paywall, app }

    /// Pure, testable router. Kept free of view state so the cold-start gating can be unit-tested directly.
    static func entryRoute(isReady: Bool, hasEverSubscribed: Bool, isPremium: Bool) -> EntryRoute {
        guard isReady else { return .loading }
        return (!hasEverSubscribed && !isPremium) ? .paywall : .app
    }

    private var route: EntryRoute {
        Self.entryRoute(isReady: subscription.isReady,
                        hasEverSubscribed: subscription.hasEverSubscribed,
                        isPremium: subscription.isPremium)
    }
    private var entryGateBinding: Binding<Bool> {
        Binding(get: { route == .paywall }, set: { _ in })
    }

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some View {
        // A stable container so the `.task` (which starts StoreKit) runs once regardless of which branch
        // shows. While `.loading` we render a neutral placeholder — NOT the TabView — so the main UI never
        // flashes before the entry paywall; the paywall cover then presents over the placeholder, never
        // over the app. A subscribed/lapsed user resolves straight to `.app`.
        ZStack {
            if route == .app {
                TabView(selection: $selectedTab) {
                    TodayView()
                        .tag(0)
                        .tabItem { Label("Today", systemImage: "checklist") }
                    HistoryView()
                        .tag(1)
                        .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                    // Week displayed 3rd (matching the mock) with a NEW tag, so Notes/Settings tags stay
                    // stable and the -tab launch args keep working.
                    WeekView()
                        .tag(4)
                        .tabItem { Label("Insights", systemImage: "chart.line.uptrend.xyaxis") }
                    NotesView()
                        .tag(2)
                        .tabItem { Label("Notes", systemImage: "note.text") }
                    SettingsView()
                        .tag(3)
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                }
            } else {
                LaunchPlaceholder()
            }
        }
        .task {
            subscription.start()   // idempotent: products + initial entitlement check + updates listener
            if !skipAuth {
                await NotificationScheduler.shared.requestAuthorization()
            }
            await NotificationScheduler.shared.refreshPermissionStatus()
            NotificationScheduler.shared.reschedule(medicines: medicines, logs: logs, escalationEnabled: escalationEnabled)
            // Diagnostics only, fire-and-forget: surface an unreachable AI backend in Settings at launch
            // instead of only on first Generate/Analyze. Never blocks the core loop above; skipped under
            // -skipAuth so UI tests stay deterministic (they use -stubAIBackendUnreachable instead).
            if !skipAuth {
                Task { await AIBackendHealth.shared.probe() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Refill the windowed horizon (and pick up any edits) whenever the app comes forward,
            // re-check that notifications are still permitted, and re-arm the background refill.
            if phase == .active {
                NotificationScheduler.shared.reschedule(medicines: medicines, logs: logs, appointments: appointments, escalationEnabled: escalationEnabled)
                BackgroundRefresh.scheduleNext()
                Task { await NotificationScheduler.shared.refreshPermissionStatus() }
                // Re-check entitlement on every foreground: a pure time-based lapse emits no
                // `Transaction.updates`, so without this a subscription that expired while the app was
                // warm would keep Premium unlocked until the next cold launch (S1).
                Task { await SubscriptionStore.shared.refresh() }
            }
        }
        // If the store had to recover on launch, the user is looking at an empty list that's
        // indistinguishable from a fresh install — surface it (must-acknowledge, not swipe-dismissable).
        .sheet(isPresented: storeNoticeBinding) {
            StoreRecoveryNotice(outcome: StoreHealth.shared.outcome) { StoreHealth.shared.acknowledge() }
                .interactiveDismissDisabled()
        }
        // Trial-gated entry paywall (blocking, no skip) — only for a never-subscribed user. It closes
        // itself once a purchase flips `isPremium`, dropping the gate condition.
        .fullScreenCover(isPresented: entryGateBinding) {
            PaywallView(context: .entry)
        }
        .preferredColorScheme(preferredScheme)
        .modifier(ForcedDynamicTypeModifier())
    }

    private var storeNoticeBinding: Binding<Bool> {
        Binding(get: { StoreHealth.shared.needsNotice }, set: { if !$0 { StoreHealth.shared.acknowledge() } })
    }

    private var skipAuth: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-skipAuth")
        #else
        false
        #endif
    }

    private static func initialTab() -> Int {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
            switch args[i + 1] {
            case "history": return 1
            case "week": return 4
            case "notes": return 2
            case "settings": return 3
            default: return 0
            }
        }
        #endif
        return 0
    }
}

/// Neutral, branded splash shown on cold launch until `SubscriptionStore` resolves the entitlement gate
/// (`EntryRoute.loading`). Renders instead of the main UI so a never-subscribed user never sees the app
/// flash before the blocking entry paywall presents over it.
private struct LaunchPlaceholder: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "checklist")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.tint)
                ProgressView()
            }
        }
        .accessibilityIdentifier("launchPlaceholder")
    }
}

/// DEBUG-only: lets a UI test pin the app to a specific Dynamic Type size via `-forceDynamicType <size>`
/// so layout-under-text-pressure is deterministic (the simulator's global content size and the
/// `-UIPreferredContentSizeCategoryName` launch arg are not reliably honoured for an SPM/XcodeGen app).
/// A no-op in Release.
private struct ForcedDynamicTypeModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        if let size = Self.forced {
            content.dynamicTypeSize(size)
        } else {
            content
        }
        #else
        content
        #endif
    }

    #if DEBUG
    static var forced: DynamicTypeSize? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-forceDynamicType"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "xSmall": return .xSmall
        case "large": return .large
        case "xLarge": return .xLarge
        case "xxLarge": return .xxLarge
        case "xxxLarge": return .xxxLarge
        case "accessibility1": return .accessibility1
        case "accessibility2": return .accessibility2
        case "accessibility3": return .accessibility3
        case "accessibility4": return .accessibility4
        case "accessibility5": return .accessibility5
        default: return nil
        }
    }
    #endif
}

/// The must-acknowledge notice shown when the store recovered on launch — so an empty list after a
/// failed load is never mistaken for a fresh install. Reassures that data was preserved (set aside,
/// not deleted), and warns when the last-resort in-memory store means new changes won't persist.
private struct StoreRecoveryNotice: View {
    let outcome: StoreLoadOutcome
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
            Text("We couldn't load your saved data")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onAcknowledge) {
                Text("OK, I understand").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("acknowledgeStoreRecovery")
        }
        .padding(28)
        .presentationDetents([.medium])
    }

    private var message: String {
        switch outcome {
        case .normal:
            return ""
        case .recreatedEmptyStore:
            return "Your previous information has been safely set aside and was not deleted. You're starting with an empty list for now — please re-add your medicines, and contact support if you need the old data recovered."
        case .inMemoryFallback:
            return "Your previous information has been safely set aside and was not deleted. Anything you change right now won't be saved — please restart the app, and contact support if the problem continues."
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Medicine.self, DoseTime.self, DoseLog.self, Note.self], inMemory: true)
}
