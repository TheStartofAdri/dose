import SwiftUI
import StoreKit

/// Where the paywall was raised from. `.entry` is the blocking first-launch gate (no dismiss — the user
/// must start the trial or restore); `.unlock` is the dismissible "resubscribe to unlock …" prompt shown
/// when a non-subscriber taps a gated feature.
enum PaywallContext: Equatable {
    case entry
    case unlock(PremiumFeature)
    case upgrade   // general resubscribe / upgrade (e.g. from Settings)
}

/// Subscription paywall. Presents the two plans (annual emphasized), starts the 7-day free trial, and
/// carries the elements App Review requires: a visible Restore Purchases button, Terms of Use (EULA) and
/// Privacy Policy links, the price, and the auto-renewing disclosure.
struct PaywallView: View {
    let context: PaywallContext

    @ObservedObject private var store = SubscriptionStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selection: PlanOption = .annual
    @State private var working = false

    enum PlanOption { case annual, monthly }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                plans
                purchaseSection
                Button("Restore Purchases") { Task { await run { await store.restore() } } }
                    .font(.subheadline)
                disclosure
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .topTrailing) {
            if context != .entry {
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .font(.title2).foregroundStyle(.secondary).padding(16)
                    .accessibilityLabel("Close")
            }
        }
        // The entry gate closes itself: once a purchase flips isPremium, RootView drops the cover.
        .onChange(of: store.isPremium) { _, now in if now && context != .entry { dismiss() } }
        .interactiveDismissDisabled(context == .entry)
    }

    // MARK: Header / value prop

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.tint)
            Text(headline).font(.title.weight(.bold)).multilineTextAlignment(.center)
            Text(subhead).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var headline: String {
        switch context {
        case .entry: "Start your 7-day free trial"
        case .unlock(let f): "Unlock \(f.title)"
        case .upgrade: "Dose Premium"
        }
    }

    private var subhead: String {
        switch context {
        case .entry:
            "Full access to Dose — reminders, tracking, reports, AI add, scanning, and the weekly view. Free for 7 days, cancel anytime."
        case .unlock, .upgrade:
            "Resubscribe to unlock reports, AI add, scanning, and the weekly view. Your reminders and history keep working either way."
        }
    }

    // MARK: Plans

    private var plans: some View {
        VStack(spacing: 12) {
            planCard(.annual, hero: true,
                     title: "Annual", badge: "Best value",
                     price: annualPriceLine, sub: annualPerMonthLine)
            planCard(.monthly, hero: false,
                     title: "Monthly", badge: nil,
                     price: monthlyPriceLine, sub: nil)
        }
    }

    private func planCard(_ option: PlanOption, hero: Bool, title: String, badge: String?,
                          price: String, sub: String?) -> some View {
        let selected = selection == option
        return Button { selection = option } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge).font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.tint, in: Capsule()).foregroundStyle(.white)
                        }
                    }
                    Text(price).font(.subheadline).foregroundStyle(.secondary)
                    if let sub { Text(sub).font(.caption).foregroundStyle(.tint) }
                }
                Spacer()
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear),
                                  lineWidth: hero ? 2 : 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // Price lines — from the loaded Product when available, with the configured fallbacks otherwise.
    // The trial is advertised ONLY when StoreKit confirms this customer is eligible: a lapsed
    // subscriber already consumed the intro offer, and a trial promise that ends in an immediate
    // charge is a trust (and guideline 2.3) violation. Unknown eligibility never over-promises.
    static func priceLine(displayPrice: String, per: String, introEligible: Bool?) -> String {
        introEligible == true ? "7-day free trial, then \(displayPrice)/\(per)" : "\(displayPrice)/\(per)"
    }
    static func ctaTitle(introEligible: Bool?) -> String {
        introEligible == true ? "Start 7-day free trial" : "Subscribe"
    }
    private var annualPriceLine: String {
        Self.priceLine(displayPrice: store.annual?.displayPrice ?? "$44.99", per: "year",
                       introEligible: store.introEligible)
    }
    private var monthlyPriceLine: String {
        Self.priceLine(displayPrice: store.monthly?.displayPrice ?? "$5.99", per: "month",
                       introEligible: store.introEligible)
    }
    private var annualPerMonthLine: String {
        if let a = store.annual { return "Just \((a.price / 12).formatted(a.priceFormatStyle))/month" }
        return "Just $3.75/month"
    }

    // MARK: CTA

    /// What the purchase area shows. `.unavailable` = StoreKit finished its first load but returned no
    /// products (Paid Apps agreement not active yet, products unavailable, or no network); `.loading` =
    /// not resolved yet; `.purchasable` = products are loaded.
    enum PurchaseState: Equatable { case loading, unavailable, purchasable }

    /// Pure, testable decision (no view state — same shape as `RootView.entryRoute`). Gated on the
    /// PRODUCT fetch having finished (not on `isReady`, which now resolves earlier from local
    /// entitlements), so a still-loading fetch is never mistaken for "unavailable".
    static func purchaseState(productsResolved: Bool, hasProducts: Bool) -> PurchaseState {
        guard productsResolved else { return .loading }
        return hasProducts ? .purchasable : .unavailable
    }

    /// Normally the purchase CTA; the friendly unavailable state (with Try Again) only when the first
    /// load finished empty. `.loading`/`.purchasable` both render the CTA, so behavior is unchanged:
    /// `productsUnavailable` shows exactly when `isReady && products.isEmpty`, the CTA otherwise.
    @ViewBuilder private var purchaseSection: some View {
        switch Self.purchaseState(productsResolved: store.productsResolved, hasProducts: !store.products.isEmpty) {
        case .unavailable: productsUnavailable
        case .loading, .purchasable: cta
        }
    }

    private var productsUnavailable: some View {
        VStack(spacing: 10) {
            Text("Subscriptions aren't available right now. Please check your connection and try again.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            // Distinguishes a network/StoreKit error from the empty-but-no-error case; the message above
            // covers both, so this is just extra detail when StoreKit actually reported an error.
            if let err = store.lastError {
                Text(err).font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            }
            Button {
                Task { await run { await store.loadProducts() } }
            } label: {
                Group {
                    if working { ProgressView().tint(.white) }
                    else { Text("Try Again").font(.headline) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(working)
        }
    }

    private var cta: some View {
        Button {
            Task { await run { if let p = selectedProduct { await store.purchase(p) } } }
        } label: {
            Group {
                if working { ProgressView().tint(.white) }
                else { Text(Self.ctaTitle(introEligible: store.introEligible)).font(.headline) }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(working || selectedProduct == nil)
    }

    private var selectedProduct: Product? {
        selection == .annual ? store.annual : store.monthly
    }

    private func run(_ work: @escaping () async -> Void) async {
        working = true; await work(); working = false
    }

    // MARK: Legal / disclosure (required for App Review)

    private var disclosure: some View {
        VStack(spacing: 8) {
            Text("Subscriptions auto-renew at the price above unless cancelled at least 24 hours before the end of the period. Manage or cancel anytime in Settings.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Terms of Use", destination: LegalLinks.terms)
                Link("Privacy Policy", destination: LegalLinks.privacy)
            }
            .font(.caption2)
        }
        .padding(.top, 4)
    }
}
