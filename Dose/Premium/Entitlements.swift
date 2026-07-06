import Foundation

/// Single source of truth for premium entitlement, and the one place premium status is documented.
///
/// Reads the **live** StoreKit subscription state from `SubscriptionStore.shared`: `true` during an active
/// trial or paid subscription, `false` when lapsed or never subscribed. Route every premium-destined
/// feature through this one seam — do not scatter StoreKit checks. Gated views observe
/// `SubscriptionStore.shared` (injected at the app root) so they re-render when the state changes.
///
/// Gated by this seam: **adherence report export (PDF)**, **AI text entry**, **label scan**, and the
/// **"This week" view** (see `PremiumFeature`).
///
/// NEVER gated by this seam: the core medication loop — Today, take/skip/undo, manual add,
/// reminders/notifications, history, notes. A lapsed user must keep receiving dose reminders, so the
/// `/Notifications` scheduling path stays entirely entitlement-free.
enum Entitlements {
    static var isPremium: Bool { SubscriptionStore.cachedIsPremium }
}
