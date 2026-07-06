import XCTest
@testable import Dose

/// Pins the paywall's purchase-area decision (`PaywallView.purchaseState`): the "Subscriptions aren't
/// available" state must appear ONLY after StoreKit resolved with zero products — never while loading,
/// and never when products are present. Locks the truth table so a future change to the condition is caught.
final class PaywallStateTests: XCTestCase {

    /// Resolved + no products ⇒ the unavailable state (Try Again), not a silently greyed CTA.
    func testReadyAndEmptyShowsUnavailable() {
        XCTAssertEqual(PaywallView.purchaseState(isReady: true, hasProducts: false), .unavailable)
    }

    /// Resolved + products present ⇒ the normal purchase CTA.
    func testReadyWithProductsShowsPurchasable() {
        XCTAssertEqual(PaywallView.purchaseState(isReady: true, hasProducts: true), .purchasable)
    }

    /// Not resolved yet ⇒ loading, regardless of the (meaningless-until-loaded) products flag — so a
    /// still-loading store is never mistaken for "unavailable".
    func testNotReadyIsLoading() {
        XCTAssertEqual(PaywallView.purchaseState(isReady: false, hasProducts: false), .loading)
        XCTAssertEqual(PaywallView.purchaseState(isReady: false, hasProducts: true), .loading)
    }
}
