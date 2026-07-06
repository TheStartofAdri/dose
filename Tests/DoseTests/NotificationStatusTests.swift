import XCTest
import UserNotifications
@testable import Dose

/// Items 3 & 4: the app must SURFACE when reminders won't reach the user — denied permission (nothing
/// fires) and 64-pending-cap truncation (some reminders dropped) — instead of failing silently.
@MainActor
final class NotificationStatusTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private lazy var now = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 6))!

    private func dailyMeds(_ n: Int) -> [MedicineSnapshot] {
        (0..<n).map { MedicineSnapshot(id: UUID(), name: "Med \($0)", dosage: nil,
                                       rules: [DoseSlotRule(hour: 8, minute: $0 % 60)]) }
    }

    // Item 3: only an explicit denial warrants the "reminders are off" banner.
    func testShouldWarnOnlyForDenied() {
        XCTAssertTrue(NotificationStatus.shouldWarn(for: .denied))
        XCTAssertFalse(NotificationStatus.shouldWarn(for: .authorized))
        XCTAssertFalse(NotificationStatus.shouldWarn(for: .provisional))
        XCTAssertFalse(NotificationStatus.shouldWarn(for: .ephemeral))
        XCTAssertFalse(NotificationStatus.shouldWarn(for: .notDetermined))
    }

    // Item 4: the visible truncation flag mirrors the plan — set when over budget, clear when under.
    func testTruncationFlagMirrorsPlan() {
        let status = NotificationStatus.shared

        let under = NotificationPlanner.plan(medicines: dailyMeds(5), now: now, escalationEnabled: false, calendar: cal)
        status.update(from: under)
        XCTAssertFalse(under.baseTruncated)
        XCTAssertFalse(status.schedulingTruncated, "under budget → no truncation notice")

        let over = NotificationPlanner.plan(medicines: dailyMeds(70), now: now, escalationEnabled: false, calendar: cal)
        status.update(from: over)
        XCTAssertTrue(over.baseTruncated)
        XCTAssertTrue(status.schedulingTruncated, "over the 64-cap → truncation notice surfaced")

        // And it clears again when the schedule fits.
        status.update(from: under)
        XCTAssertFalse(status.schedulingTruncated)
    }
}
