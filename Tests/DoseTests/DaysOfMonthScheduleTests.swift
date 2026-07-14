import XCTest
@testable import Dose

/// C1: a `daysOfMonth` schedule must never silently skip a month. A requested day beyond a short
/// month's length (e.g. "the 31st" in April, "the 30th" in February) clamps to that month's LAST day,
/// so a monthly medication reminder still fires every month.
///
/// FAIL-BEFORE: `applies` matched the calendar day exactly, so `[31]` produced zero slots in 30-day
/// months and February. PASS-AFTER: it fires on the last day of those months.
final class DaysOfMonthScheduleTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }
    private func med(_ daysOfMonth: [Int]) -> MedicineSnapshot {
        MedicineSnapshot(id: UUID(), name: "Monthly", dosage: "1 tab",
                         rules: [DoseSlotRule(hour: 8, minute: 0, daysOfMonth: daysOfMonth)],
                         createdAt: .distantPast)
    }
    private func fires(_ daysOfMonth: [Int], on day: Date) -> Bool {
        !ExecutionEngine.scheduledSlots(medicines: [med(daysOfMonth)], on: day, calendar: cal).isEmpty
    }

    // MARK: Clamp — the bug

    func testDay31FiresOnLastDayOf30DayMonth() {
        XCTAssertTrue(fires([31], on: date(2026, 4, 30)), "31st clamps to Apr 30")
        XCTAssertFalse(fires([31], on: date(2026, 4, 29)), "not the day before the last")
    }

    func testDay31FiresOnLastDayOfFebruary() {
        XCTAssertTrue(fires([31], on: date(2026, 2, 28)), "31st clamps to Feb 28 (non-leap)")
        XCTAssertFalse(fires([31], on: date(2026, 2, 27)))
    }

    func testDay30FiresOnFeb28() {
        XCTAssertTrue(fires([30], on: date(2026, 2, 28)), "30th clamps to Feb 28")
    }

    func testDay29FiresOnLeapFeb29AndNonLeapFeb28() {
        XCTAssertTrue(fires([29], on: date(2028, 2, 29)), "leap year has a real 29th")
        XCTAssertTrue(fires([29], on: date(2026, 2, 28)), "non-leap clamps the 29th to Feb 28")
    }

    // MARK: No over-firing — the clamp must not add spurious days

    func testDay31DoesNotFireOnThe30thOfA31DayMonth() {
        // January HAS a 31st, so the "31st" schedule must fire only on Jan 31, never clamp onto Jan 30.
        XCTAssertFalse(fires([31], on: date(2026, 1, 30)), "no clamp when the real day exists")
        XCTAssertTrue(fires([31], on: date(2026, 1, 31)))
    }

    func testExactMidMonthDayUnaffected() {
        XCTAssertTrue(fires([15], on: date(2026, 2, 15)))
        XCTAssertFalse(fires([15], on: date(2026, 2, 14)))
        XCTAssertFalse(fires([15], on: date(2026, 2, 28)), "the 15th never clamps to month-end")
    }

    func testClampProducesExactlyOneSlotWhenBothRealAndOverflowDaysRequested() {
        // [30, 31] in April: the 30th (real) and the 31st (clamps to 30) resolve to the same day —
        // exactly one slot, not two.
        let slots = ExecutionEngine.scheduledSlots(medicines: [med([30, 31])], on: date(2026, 4, 30), calendar: cal)
        XCTAssertEqual(slots.count, 1)
    }
}
