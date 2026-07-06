import XCTest
@testable import Dose

/// Feature B: the read-only "This week" projection. Every test drives the SAME engine the week view
/// uses (`ExecutionEngine.scheduledSlots(medicines:on:)`), and the last test proves it can't diverge
/// from Today.
final class WeekScheduleTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private lazy var start = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!  // a fixed day

    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: start)! }
    private func slots(_ meds: [MedicineSnapshot], _ offset: Int) -> [ScheduledSlot] {
        ExecutionEngine.scheduledSlots(medicines: meds, on: day(offset), calendar: cal)
    }

    private func med(rules: [DoseSlotRule], createdAt: Date? = nil, endDate: Date? = nil) -> MedicineSnapshot {
        MedicineSnapshot(id: UUID(), name: "Med", dosage: "5 mg", rules: rules,
                         createdAt: createdAt ?? start, endDate: endDate)
    }

    func testDailyMedAppearsEveryDay() {
        let meds = [med(rules: [DoseSlotRule(hour: 8, minute: 0)])]
        for offset in 0..<7 {
            XCTAssertEqual(slots(meds, offset).count, 1, "daily med scheduled on day \(offset)")
        }
    }

    func testSpecificWeekdayMedAppearsOnlyOnThatWeekday() {
        // Target the weekday of day 2, so within the 7-day window exactly day 2 matches.
        let targetWeekday = cal.component(.weekday, from: day(2))
        let meds = [med(rules: [DoseSlotRule(hour: 8, minute: 0, weekdays: [targetWeekday])])]
        for offset in 0..<7 {
            let expected = offset == 2 ? 1 : 0
            XCTAssertEqual(slots(meds, offset).count, expected, "weekday med on day \(offset)")
        }
    }

    func testEveryNDaysMedAppearsOnAnchoredDays() {
        // Every 3 days anchored at start → days 0, 3, 6 within the window.
        let meds = [med(rules: [DoseSlotRule(hour: 8, minute: 0, intervalDays: 3, anchorDate: start)])]
        for offset in 0..<7 {
            let expected = (offset % 3 == 0) ? 1 : 0
            XCTAssertEqual(slots(meds, offset).count, expected, "every-3-days med on day \(offset)")
        }
    }

    func testEndDateStopsMedAfterThatDate() {
        // Daily, but the course ends on day 2 (inclusive) → days 0–2 only.
        let meds = [med(rules: [DoseSlotRule(hour: 8, minute: 0)], endDate: day(2))]
        for offset in 0..<7 {
            let expected = offset <= 2 ? 1 : 0
            XCTAssertEqual(slots(meds, offset).count, expected, "bounded course on day \(offset)")
        }
    }

    func testDayWithNothingScheduledIsEmpty() {
        // A med only on day 2's weekday → the other six days are empty (the "Nothing scheduled" state).
        let targetWeekday = cal.component(.weekday, from: day(2))
        let meds = [med(rules: [DoseSlotRule(hour: 8, minute: 0, weekdays: [targetWeekday])])]
        XCTAssertTrue(slots(meds, 0).isEmpty)
        XCTAssertTrue(slots(meds, 1).isEmpty)
        XCTAssertFalse(slots(meds, 2).isEmpty)
        XCTAssertTrue(slots(meds, 3).isEmpty)
    }

    /// CRITICAL: the week view's occurrences for a date are exactly what Today computes for that date.
    /// Same engine, no parallel calculation — so they can never drift.
    func testWeekSlotsMatchTodaysDosesForSameDate() {
        let meds = [
            med(rules: [DoseSlotRule(hour: 8, minute: 0)]),                                   // daily
            med(rules: [DoseSlotRule(hour: 21, minute: 0)]),                                  // daily evening
            med(rules: [DoseSlotRule(hour: 9, minute: 0, intervalDays: 2, anchorDate: start)]), // every other day
            med(rules: [DoseSlotRule(hour: 7, minute: 0)], endDate: day(3)),                  // bounded
        ]
        for offset in 0..<7 {
            let d = day(offset)
            let weekSlots = ExecutionEngine.scheduledSlots(medicines: meds, on: d, calendar: cal)
            let todays = ExecutionEngine.todaysDoses(medicines: meds, logs: [], now: d, calendar: cal)
            XCTAssertEqual(weekSlots.map(\.scheduledFor), todays.map(\.scheduledFor),
                           "week vs Today scheduled times agree on day \(offset)")
            XCTAssertEqual(weekSlots.map(\.id), todays.map(\.id),
                           "week vs Today slot identities agree on day \(offset)")
        }
    }
}
