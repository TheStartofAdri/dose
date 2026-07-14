import XCTest
@testable import Dose

/// Phase 1 (refill reminders): the pure run-out projection. Stock is DERIVED from taken logs since the
/// last refill — no mutated counter — so it stays consistent with Undo and log edits automatically.
final class RefillCalculatorTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let medID = UUID()
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }
    private func taken(_ at: Date) -> DoseLogSnapshot {
        DoseLogSnapshot(medicineID: medID, scheduledFor: at, action: .taken, actionedAt: at)
    }

    func testUnitsRemainingDerivedFromTakenLogsSinceRefill() {
        let refill = date(2026, 6, 1)
        var logs = (0..<10).map { taken(date(2026, 6, 2 + $0)) }        // 10 taken on/after refill
        logs += [taken(date(2026, 5, 30)), taken(date(2026, 5, 31))]    // 2 taken BEFORE → not counted
        XCTAssertEqual(RefillCalculator.unitsRemaining(unitsAtRefill: 30, refillDate: refill, unitsPerDose: 1, logs: logs), 20)
    }

    func testUnitsRemainingHonorsUnitsPerDoseAndClampsAtZero() {
        let refill = date(2026, 6, 1)
        let logs = (0..<20).map { taken(date(2026, 6, 2 + $0)) }        // 20 doses × 2 units = 40 > 30
        XCTAssertEqual(RefillCalculator.unitsRemaining(unitsAtRefill: 30, refillDate: refill, unitsPerDose: 2, logs: logs), 0)
    }

    func testUnitsRemainingNilWhenNotTracking() {
        XCTAssertNil(RefillCalculator.unitsRemaining(unitsAtRefill: nil, refillDate: date(2026, 6, 1), unitsPerDose: 1, logs: []))
        XCTAssertNil(RefillCalculator.unitsRemaining(unitsAtRefill: 30, refillDate: nil, unitsPerDose: 1, logs: []))
    }

    func testAverageDosesPerDay() {
        let twiceDaily = [DoseSlotRule(hour: 8, minute: 0), DoseSlotRule(hour: 20, minute: 0)]
        XCTAssertEqual(RefillCalculator.averageDosesPerDay(rules: twiceDaily, from: date(2026, 6, 1), window: 28, calendar: cal), 2.0, accuracy: 0.001)
        let everyThree = [DoseSlotRule(hour: 8, minute: 0, intervalDays: 3, anchorDate: date(2026, 6, 1))]
        XCTAssertEqual(RefillCalculator.averageDosesPerDay(rules: everyThree, from: date(2026, 6, 1), window: 30, calendar: cal), 10.0 / 30.0, accuracy: 0.02)
        XCTAssertEqual(RefillCalculator.averageDosesPerDay(rules: [], from: date(2026, 6, 1), calendar: cal), 0)
    }

    func testDaysOfSupply() {
        XCTAssertEqual(RefillCalculator.daysOfSupply(remaining: 20, unitsPerDose: 1, dosesPerDay: 2), 10)
        XCTAssertNil(RefillCalculator.daysOfSupply(remaining: 20, unitsPerDose: 1, dosesPerDay: 0), "no scheduled usage → can't project")
        XCTAssertNil(RefillCalculator.daysOfSupply(remaining: nil, unitsPerDose: 1, dosesPerDay: 2))
    }

    func testNeedsRefillSoon() {
        XCTAssertTrue(RefillCalculator.needsRefillSoon(daysOfSupply: 5, thresholdDays: 7))
        XCTAssertTrue(RefillCalculator.needsRefillSoon(daysOfSupply: 7, thresholdDays: 7), "at the threshold counts")
        XCTAssertFalse(RefillCalculator.needsRefillSoon(daysOfSupply: 10, thresholdDays: 7))
        XCTAssertFalse(RefillCalculator.needsRefillSoon(daysOfSupply: nil, thresholdDays: 7))
        XCTAssertFalse(RefillCalculator.needsRefillSoon(daysOfSupply: 5, thresholdDays: nil))
    }

    /// End-to-end: 30 tablets, 1/dose, twice daily, refilled today, none taken → 15 days supply.
    func testEndToEndProjection() {
        let refill = date(2026, 6, 1)
        let rules = [DoseSlotRule(hour: 8, minute: 0), DoseSlotRule(hour: 20, minute: 0)]
        let remaining = RefillCalculator.unitsRemaining(unitsAtRefill: 30, refillDate: refill, unitsPerDose: 1, logs: [])
        let perDay = RefillCalculator.averageDosesPerDay(rules: rules, from: refill, window: 28, calendar: cal)
        let days = RefillCalculator.daysOfSupply(remaining: remaining, unitsPerDose: 1, dosesPerDay: perDay)
        XCTAssertEqual(days, 15)
        XCTAssertFalse(RefillCalculator.needsRefillSoon(daysOfSupply: days, thresholdDays: 7))
    }
}
