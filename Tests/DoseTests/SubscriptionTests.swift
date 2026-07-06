import XCTest
@testable import Dose

/// Subscription entitlement logic + the safety guarantee that reminders are NEVER gated.
@MainActor
final class SubscriptionTests: XCTestCase {

    // MARK: - Pure entitlement decision (no StoreKit needed)

    func testActivePaidIsEntitled() {
        let future = Date(timeIntervalSinceNow: 30 * 86_400)
        XCTAssertTrue(SubscriptionStore.isEntitled([EntitlementSnapshot(expiration: future, isRevoked: false)]),
                      "an active paid subscription is premium")
    }

    func testActiveTrialIsEntitled() {
        // A free trial is just an active entitlement whose expiration is the trial end (in the future).
        let trialEnd = Date(timeIntervalSinceNow: 7 * 86_400)
        XCTAssertTrue(SubscriptionStore.isEntitled([EntitlementSnapshot(expiration: trialEnd, isRevoked: false)]),
                      "a dose user in the 7-day trial has full access")
    }

    func testNonExpiringIsEntitled() {
        XCTAssertTrue(SubscriptionStore.isEntitled([EntitlementSnapshot(expiration: nil, isRevoked: false)]))
    }

    func testExpiredIsNotEntitled() {
        let past = Date(timeIntervalSinceNow: -86_400)
        XCTAssertFalse(SubscriptionStore.isEntitled([EntitlementSnapshot(expiration: past, isRevoked: false)]),
                       "a lapsed subscription is not premium")
    }

    func testRevokedIsNotEntitled() {
        let future = Date(timeIntervalSinceNow: 30 * 86_400)
        XCTAssertFalse(SubscriptionStore.isEntitled([EntitlementSnapshot(expiration: future, isRevoked: true)]),
                       "a refunded/revoked transaction is not premium even before its period ends")
    }

    func testNoEntitlementsIsNotEntitled() {
        XCTAssertFalse(SubscriptionStore.isEntitled([]), "a never-subscribed user is not premium")
    }

    func testAnyActiveEntitlementAmongExpiredIsEntitled() {
        let past = Date(timeIntervalSinceNow: -86_400)
        let future = Date(timeIntervalSinceNow: 86_400)
        XCTAssertTrue(SubscriptionStore.isEntitled([
            EntitlementSnapshot(expiration: past, isRevoked: false),
            EntitlementSnapshot(expiration: future, isRevoked: false),
        ]), "one active entitlement is enough")
    }

    // MARK: - The seam reads the store

    func testEntitlementSeamReflectsStore() {
        SubscriptionStore.shared.setPremiumForTesting(true)
        XCTAssertTrue(Entitlements.isPremium, "Entitlements.isPremium reflects an active subscription")
        SubscriptionStore.shared.setPremiumForTesting(false)
        XCTAssertFalse(Entitlements.isPremium, "Entitlements.isPremium reflects a lapsed subscription")
    }

    // MARK: - Reminders are NEVER gated (the safety guarantee)

    func testRemindersScheduleEvenWhenNotPremium() {
        SubscriptionStore.shared.setPremiumForTesting(false)
        XCTAssertFalse(Entitlements.isPremium, "precondition: not premium (lapsed/never)")

        // An active, confirmed daily med still schedules on-time dose reminders — the planner never reads
        // `isPremium`, so a lapsed user keeps being reminded to take their medication.
        let med = MedicineSnapshot(id: UUID(), name: "Aspirin", dosage: "100 mg",
                                   rules: [DoseSlotRule(hour: 8, minute: 0)])
        let plan = NotificationPlanner.plan(medicines: [med], logs: [], now: .now, escalationEnabled: false)
        XCTAssertFalse(plan.onTime.isEmpty,
                       "a non-premium (lapsed) user MUST keep getting dose reminders — scheduling is entitlement-free")
    }

    func testReminderSchedulingIdenticalRegardlessOfSubscription() {
        let med = MedicineSnapshot(id: UUID(), name: "Aspirin", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0)])
        SubscriptionStore.shared.setPremiumForTesting(true)
        let premium = NotificationPlanner.plan(medicines: [med], logs: [], now: .now, escalationEnabled: false).onTime.count
        SubscriptionStore.shared.setPremiumForTesting(false)
        let lapsed = NotificationPlanner.plan(medicines: [med], logs: [], now: .now, escalationEnabled: false).onTime.count
        XCTAssertGreaterThan(lapsed, 0)
        XCTAssertEqual(premium, lapsed, "reminder scheduling is identical whether subscribed or lapsed")
    }

    // MARK: - Gate policy is locked

    func testExactlyFourPremiumFeatures() {
        XCTAssertEqual(Set(PremiumFeature.allCases),
                       [.reportExport, .aiTextEntry, .scanLabel, .weeklyView],
                       "exactly these four features are gated; the core loop is never in the gated set")
    }
}
