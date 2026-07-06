import XCTest
@testable import Dose

/// BUG 3: cold-start gating. The entry paywall must not be preceded by a flash of the main UI. The fix
/// routes to `.loading` until StoreKit resolves (`isReady`), so the app is never rendered before the gate
/// is known. Before the fix the main UI showed whenever the (false) paywall condition wasn't met — i.e. a
/// not-yet-ready new user saw the TabView, then the paywall dropped over it. These pin the pure router.
final class RootRoutingTests: XCTestCase {

    /// The decisive fail-before/pass-after case: not ready ⇒ neither app nor paywall, just `.loading`.
    /// Old logic (paywall iff ready&&!ever&&!premium, else app) returned `.app` here — the flash.
    func testNotReadyRoutesToLoadingNotApp() {
        let route = RootView.entryRoute(isReady: false, hasEverSubscribed: false, isPremium: false)
        XCTAssertEqual(route, .loading, "while StoreKit is unresolved the main UI must not render")
        XCTAssertNotEqual(route, .app, "the app must not flash before the gate resolves")
    }

    /// Ready + brand-new user (never subscribed, not premium) ⇒ the blocking entry paywall.
    func testReadyNewUserRoutesToPaywall() {
        XCTAssertEqual(RootView.entryRoute(isReady: true, hasEverSubscribed: false, isPremium: false), .paywall)
    }

    /// Ready + lapsed user (has subscribed before) ⇒ enters the app, no paywall (the must-not-break case).
    func testReadyLapsedUserRoutesToApp() {
        XCTAssertEqual(RootView.entryRoute(isReady: true, hasEverSubscribed: true, isPremium: false), .app)
    }

    /// Ready + active premium ⇒ app (covers the just-purchased / restored subscriber).
    func testReadyPremiumRoutesToApp() {
        XCTAssertEqual(RootView.entryRoute(isReady: true, hasEverSubscribed: false, isPremium: true), .app)
        XCTAssertEqual(RootView.entryRoute(isReady: true, hasEverSubscribed: true, isPremium: true), .app)
    }

    /// Readiness gates everything: even a would-be paywall user is `.loading` until ready (no flash).
    func testLoadingTakesPrecedenceOverPaywall() {
        XCTAssertEqual(RootView.entryRoute(isReady: false, hasEverSubscribed: false, isPremium: false), .loading)
        XCTAssertEqual(RootView.entryRoute(isReady: false, hasEverSubscribed: true, isPremium: true), .loading)
    }
}
