import XCTest
@testable import Dose

/// Phase 1: the notification planner arms one "running low" refill reminder for a stock-tracking
/// medicine whose projected run-out crosses its threshold within the horizon — at lowest priority.
final class RefillReminderPlanTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }
    private func med(units: Int?, threshold: Int?, perDose: Int = 1, refillDate: Date? = nil) -> MedicineSnapshot {
        MedicineSnapshot(id: UUID(), name: "Aspirin", dosage: nil,
                         rules: [DoseSlotRule(hour: 8, minute: 0), DoseSlotRule(hour: 20, minute: 0)],
                         unitsAtRefill: units, refillDate: refillDate, unitsPerDose: perDose,
                         refillThresholdDays: threshold)
    }

    func testLowStockMedArmsRefillReminder() {
        let now = date(2026, 6, 1, 9)
        // 10 tablets, twice daily → 5 days of supply; threshold 7 → already below → arm.
        let m = med(units: 10, threshold: 7, refillDate: date(2026, 6, 1))
        let plan = NotificationPlanner.plan(medicines: [m], logs: [], now: now, escalationEnabled: false, calendar: cal)
        XCTAssertEqual(plan.refills.count, 1)
        XCTAssertEqual(plan.refills.first?.id, NotificationPlanner.medRefillID(m.id))
        XCTAssertGreaterThan(plan.refills.first!.fireDate, now)
    }

    func testWellStockedMedDoesNotArm() {
        let now = date(2026, 6, 1, 9)
        // 200 tablets, twice daily → ~100 days; crossing ~93 days out (> the 7-day window) → not armed.
        let m = med(units: 200, threshold: 7, refillDate: date(2026, 6, 1))
        let plan = NotificationPlanner.plan(medicines: [m], logs: [], now: now, escalationEnabled: false, calendar: cal)
        XCTAssertTrue(plan.refills.isEmpty)
    }

    func testNotTrackingProducesNoRefillReminder() {
        let now = date(2026, 6, 1, 9)
        let plan = NotificationPlanner.plan(medicines: [med(units: nil, threshold: nil)], logs: [],
                                            now: now, escalationEnabled: false, calendar: cal)
        XCTAssertTrue(plan.refills.isEmpty)
    }

    /// Consumption is derived from taken logs: enough takes since refill push a well-stocked med under.
    func testConsumptionSinceRefillDrivesTheReminder() {
        let now = date(2026, 6, 20, 9)
        let refill = date(2026, 6, 1)
        // 40 tablets at refill, twice daily. 32 taken since → 8 left → 4 days supply, threshold 7 → arm.
        let m = med(units: 40, threshold: 7, refillDate: refill)
        let logs = (0..<32).map {
            DoseLogSnapshot(medicineID: m.id, scheduledFor: date(2026, 6, 2), action: .taken,
                            actionedAt: refill.addingTimeInterval(Double($0) * 3600))
        }
        let plan = NotificationPlanner.plan(medicines: [m], logs: logs, now: now, escalationEnabled: false, calendar: cal)
        XCTAssertEqual(plan.refills.count, 1)
    }
}
