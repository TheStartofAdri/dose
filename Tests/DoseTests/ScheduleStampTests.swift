import XCTest
@testable import Dose

/// P2 #4: `saveEdit` stamps `scheduleChangedAt` only on a REAL schedule change. It compares each rule's
/// canonical scheduling identity (`MedicineWriter.isScheduleChange`), not raw fields — so a behaviorally
/// identical edit (notably "all seven weekdays" ↔ "every day") must NOT stamp. A spurious stamp silently
/// wipes genuine past misses from adherence/streak, so this over-stamp is a data-correctness bug.
/// Fail-before: the old raw `Set<DoseSlotRule>` compare saw all-7 and every-day as different → stamped.
final class ScheduleStampTests: XCTestCase {
    private func rule(_ h: Int, weekdays: [Int] = [], intervalDays: Int = 0,
                      anchorDate: Date? = nil, daysOfMonth: [Int] = []) -> DoseSlotRule {
        DoseSlotRule(hour: h, minute: 0, weekdays: weekdays, intervalDays: intervalDays,
                     anchorDate: anchorDate, daysOfMonth: daysOfMonth)
    }

    /// The headline no-op: all-seven-weekdays and every-day fire on identical days → not a change.
    func testAllSevenWeekdaysEqualsEveryDay() {
        XCTAssertFalse(MedicineWriter.isScheduleChange(from: [rule(8, weekdays: [1, 2, 3, 4, 5, 6, 7])],
                                                       to: [rule(8)]),
                       "all seven weekdays and 'every day' schedule identically — no stamp")
        XCTAssertFalse(MedicineWriter.isScheduleChange(from: [rule(8)],
                                                       to: [rule(8, weekdays: [7, 6, 5, 4, 3, 2, 1])]),
                       "reverse toggle (order-independent) is also no change")
    }

    /// A genuine weekday narrowing IS a change (guard against over-collapsing everything to "no change").
    func testNarrowingWeekdaysIsAChange() {
        XCTAssertTrue(MedicineWriter.isScheduleChange(from: [rule(8)],
                                                      to: [rule(8, weekdays: [2, 4, 6])]),
                      "every day → Mon/Wed/Fri fires on fewer days — a real change")
    }

    /// A time change is a change; an unchanged schedule is not (name-only edits must not stamp).
    func testTimeChangeAndIdentityCases() {
        XCTAssertTrue(MedicineWriter.isScheduleChange(from: [rule(8)], to: [rule(9)]),
                      "08:00 → 09:00 is a real schedule change")
        XCTAssertFalse(MedicineWriter.isScheduleChange(from: [rule(8), rule(20)], to: [rule(20), rule(8)]),
                       "same two times in a different order is not a change")
    }

    /// Precedence-shadowed fields don't count: with days-of-month active, the (ignored) weekdays value
    /// changing is not a real schedule change — `applies` never consults weekdays when daysOfMonth is set.
    func testShadowedWeekdaysUnderDaysOfMonthIsNotAChange() {
        XCTAssertFalse(MedicineWriter.isScheduleChange(from: [rule(8, weekdays: [2], daysOfMonth: [1, 15])],
                                                       to: [rule(8, weekdays: [3], daysOfMonth: [1, 15])]),
                       "days-of-month takes precedence, so the ignored weekdays field changing is a no-op")
        XCTAssertTrue(MedicineWriter.isScheduleChange(from: [rule(8, daysOfMonth: [1, 15])],
                                                      to: [rule(8, daysOfMonth: [1, 20])]),
                      "but changing the actual days-of-month IS a change")
    }
}
