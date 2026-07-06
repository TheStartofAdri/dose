import XCTest
@testable import Dose

/// Pins the paywall's purchase-area decision (`PaywallView.purchaseState`): the "Subscriptions aren't
/// available" state must appear ONLY after the product fetch resolved with zero products — never while
/// loading, and never when products are present. Gated on `productsResolved` (NOT `isReady`, which now
/// resolves earlier from local entitlements so routing never waits on the network). Locks the truth
/// table so a future change to the condition is caught.
final class PaywallStateTests: XCTestCase {

    /// Fetch finished + no products ⇒ the unavailable state (Try Again), not a silently greyed CTA.
    func testResolvedAndEmptyShowsUnavailable() {
        XCTAssertEqual(PaywallView.purchaseState(productsResolved: true, hasProducts: false), .unavailable)
    }

    /// Fetch finished + products present ⇒ the normal purchase CTA.
    func testResolvedWithProductsShowsPurchasable() {
        XCTAssertEqual(PaywallView.purchaseState(productsResolved: true, hasProducts: true), .purchasable)
    }

    /// Fetch not finished yet ⇒ loading, regardless of the (meaningless-until-loaded) products flag —
    /// so a still-loading fetch is never mistaken for "unavailable".
    func testUnresolvedIsLoading() {
        XCTAssertEqual(PaywallView.purchaseState(productsResolved: false, hasProducts: false), .loading)
        XCTAssertEqual(PaywallView.purchaseState(productsResolved: false, hasProducts: true), .loading)
    }
}
