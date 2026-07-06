import Foundation
import StoreKit

/// Value snapshot of one entitlement — the only thing the premium decision needs, so `isEntitled` is
/// unit-testable without constructing a StoreKit `Transaction` (which can't be built in a test).
struct EntitlementSnapshot: Sendable, Equatable {
    let expiration: Date?   // nil = non-expiring; otherwise the subscription/trial period end
    let isRevoked: Bool     // refunded / revoked by Apple
}

/// The live StoreKit 2 subscription engine and single backing store for `Entitlements.isPremium`.
///
/// Holds the cached premium state, loads the products, and listens to `Transaction.updates` so renewals,
/// lapses, and cancellations reflect **without an app restart**. A singleton (matching
/// `NotificationScheduler.shared` / `StoreHealth.shared`), injected into the environment at the app root so
/// gated views re-render when entitlement changes — the *decision* always routes through
/// `Entitlements.isPremium`.
@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    /// Active subscription OR trial. Drives the UI (observed) and mirrors into `cachedIsPremium` so the
    /// `Entitlements.isPremium` seam can read it synchronously from any (nonisolated) context.
    @Published private(set) var isPremium: Bool = false {
        didSet { Self.cachedIsPremium = isPremium }
    }

    /// Nonisolated mirror of `isPremium`, written only on the main actor (via `isPremium`'s `didSet`) and
    /// read on the main actor by `Entitlements.isPremium` / gated views — so the single seam stays a
    /// plain synchronous `Bool` without actor friction.
    nonisolated(unsafe) static var cachedIsPremium: Bool = false
    /// Whether the user has EVER started a subscription/trial (computed from `Transaction.all`, so it
    /// survives reinstall). Once true the entry paywall is never shown again — a lapsed user keeps
    /// entering the app and getting reminders; only the premium extras lock.
    @Published private(set) var hasEverSubscribed: Bool = false
    /// The first entitlement check has completed — gates the entry paywall so it never flashes before
    /// StoreKit has loaded. Deliberately does NOT wait for the product fetch (see `start()`).
    @Published private(set) var isReady: Bool = false
    /// The first product fetch has FINISHED (success or failure) — gates the paywall's "unavailable"
    /// state so a still-loading store is never mistaken for "no products".
    @Published private(set) var productsResolved: Bool = false
    /// Whether THIS customer is eligible for the introductory offer (the 7-day free trial), `nil`
    /// until resolved. Eligibility is per subscription group and both plans share one group, so a
    /// single answer covers both. A lapsed subscriber has consumed the offer → `false` — the paywall
    /// must then show the plain price, never a trial promise that ends in an immediate charge.
    @Published private(set) var introEligible: Bool?
    @Published private(set) var products: [Product] = []
    @Published var lastError: String?

    static let monthlyID = "com.thestartofadri.dose.premium.monthly"
    static let annualID = "com.thestartofadri.dose.premium.annual"
    static var productIDs: Set<String> { [monthlyID, annualID] }

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var annual: Product? { products.first { $0.id == Self.annualID } }

    private var updatesTask: Task<Void, Never>?

    private init() {}

    /// Pure, unit-testable decision: premium iff any non-revoked entitlement is unexpired (a trial is just
    /// an active entitlement whose `expiration` is the trial end).
    static func isEntitled(_ entitlements: [EntitlementSnapshot], now: Date = .now) -> Bool {
        entitlements.contains { !$0.isRevoked && ($0.expiration == nil || $0.expiration! > now) }
    }

    /// Idempotently start the updates listener, load products, and run the initial entitlement check.
    func start() {
        #if DEBUG
        if forcedForTesting { isReady = true; return }   // keep the test-forced state; don't hit StoreKit
        #endif
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let txn) = update { await txn.finish() }
                await self?.refresh()
            }
        }
        // Entitlements resolve from the LOCAL StoreKit cache in milliseconds (even offline); the
        // product fetch is a network call that can take seconds or fail outright. Route on
        // entitlements first, so a returning subscriber on a flaky network reaches the app instantly
        // instead of staring at the launch placeholder — and an offline first launch reaches the
        // paywall's retry state rather than a dead placeholder. Products load lazily for the paywall.
        Task { await refresh(); isReady = true; await loadProducts() }
    }

    func loadProducts() async {
        defer { productsResolved = true }
        do {
            products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price }
            if let subscription = products.first?.subscription {
                introEligible = await subscription.isEligibleForIntroOffer
            }
        } catch { lastError = error.localizedDescription }
    }

    /// Recompute `isPremium` from current entitlements and `hasEverSubscribed` from all transactions.
    func refresh() async {
        var current: [EntitlementSnapshot] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let txn) = result, Self.productIDs.contains(txn.productID) else { continue }
            current.append(EntitlementSnapshot(expiration: txn.expirationDate, isRevoked: txn.revocationDate != nil))
        }
        isPremium = Self.isEntitled(current)

        if !current.isEmpty {
            hasEverSubscribed = true
        } else {
            var ever = false
            for await result in Transaction.all {
                if case .verified(let txn) = result, Self.productIDs.contains(txn.productID) { ever = true; break }
            }
            hasEverSubscribed = ever
        }
    }

    /// Buy a plan (starts the free trial for a first-time subscriber). Verifies, finishes, and refreshes.
    func purchase(_ product: Product) async {
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let txn) = verification { await txn.finish() }
                await refresh()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Restore Purchases — re-grants entitlement from the customer's existing transactions.
    func restore() async {
        do { try await AppStore.sync(); await refresh() }
        catch { lastError = error.localizedDescription }
    }

    #if DEBUG
    private(set) var forcedForTesting = false

    /// Test seam: force the cached premium flag so entitlement/gate/reminder unit and UI tests don't need a
    /// live StoreKit session. Persists (start()/refresh() won't overwrite it). Never compiled into Release.
    func setPremiumForTesting(_ value: Bool) {
        forcedForTesting = true
        isPremium = value
        hasEverSubscribed = true   // a forced session is past the entry gate
        isReady = true
        productsResolved = true    // forced sessions never fetch — don't leave the paywall "loading"
    }
    #endif
}
