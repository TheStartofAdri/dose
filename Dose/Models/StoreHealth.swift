import Foundation
import Observation

/// Observable, app-wide notice that the persistent store had to RECOVER on launch — so the user isn't
/// silently shown an empty medicine list that's indistinguishable from a fresh install. For a med app,
/// "your data couldn't load and we didn't tell you" is dangerous (the user may assume nothing is
/// scheduled, or re-add duplicates), so a recovery surfaces a one-time, must-acknowledge notice.
///
/// Seeded once at launch from `DoseStore.lastLoadOutcome`. Mirrors the `NotificationStatus` pattern.
@MainActor
@Observable
final class StoreHealth {
    static let shared = StoreHealth()

    var outcome: StoreLoadOutcome = .normal
    private(set) var acknowledged = false

    /// Show the recovery notice while a non-normal load hasn't been acknowledged yet.
    var needsNotice: Bool { outcome != .normal && !acknowledged }

    func acknowledge() { acknowledged = true }

    /// Apply the real load outcome from `DoseStore.lastLoadOutcome`. A DEBUG simulate arg (which sets a
    /// non-normal outcome in `init`) wins, so seeding only applies when nothing has been set yet.
    func seedFromRealLoad(_ realOutcome: StoreLoadOutcome) {
        if outcome == .normal { outcome = realOutcome }
    }

    private init() {
        #if DEBUG
        // Screenshot/UITest seams so the recovery notice can be exercised without corrupting a store.
        if CommandLine.arguments.contains("-simulateStoreInMemory") { outcome = .inMemoryFallback }
        else if CommandLine.arguments.contains("-simulateStoreRecovery") { outcome = .recreatedEmptyStore }
        #endif
    }
}
