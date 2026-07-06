import XCTest
@testable import Dose

/// M1: two dose-time rules that resolve to the same minute (e.g. "Add time" seeds a copy of the last
/// picker) must NOT become two slots — that would collide as identical ForEach ids on Today/Week and
/// double-count adherence. De-dup is enforced authoritatively in the engine and at the draft source.
/// Fail-before: each of these emitted/counted 2.
final class DuplicateRuleDedupTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let medID = UUID()
    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    /// A medicine carrying two identical rules (same hour:minute).
    private func dupRuleMed() -> MedicineSnapshot {
        MedicineSnapshot(id: medID, name: "X", dosage: nil,
                         rules: [DoseSlotRule(hour: 8, minute: 0), DoseSlotRule(hour: 8, minute: 0)])
    }

    // MARK: engine — slot expansion

    func testScheduledSlotsDeDupsIdenticalRules() {
        let slots = ExecutionEngine.scheduledSlots(medicines: [dupRuleMed()], on: at(2026, 6, 16), calendar: cal)
        XCTAssertEqual(slots.count, 1, "two identical rules must yield one slot, not two")
        XCTAssertEqual(Set(slots.map(\.id)).count, slots.count, "slot ids unique → no ForEach collision")
    }

    func testTodaysDosesDeDupsIdenticalRules() {
        let doses = ExecutionEngine.todaysDoses(medicines: [dupRuleMed()], logs: [], now: at(2026, 6, 16, 12), calendar: cal)
        XCTAssertEqual(doses.count, 1)
        XCTAssertEqual(Set(doses.map(\.id)).count, doses.count, "TodayDose ids unique")
    }

    // MARK: engine — adherence

    func testAdherenceCountsDuplicateRuleSlotOnce_taken() {
        let now = at(2026, 6, 16, 12, 0)
        let log = DoseLogSnapshot(medicineID: medID, scheduledFor: at(2026, 6, 16, 8, 0),
                                  action: .taken, actionedAt: at(2026, 6, 16, 8, 1))
        let day = AdherenceCalculator.days(medicines: [dupRuleMed()], logs: [log], now: now, days: 1, calendar: cal).last!
        XCTAssertEqual(day.taken, 1, "one real dose counted once despite the duplicate rule")
        XCTAssertEqual(day.counted, 1)
    }

    func testAdherenceCountsDuplicateRuleSlotOnce_missed() {
        let now = at(2026, 6, 16, 12, 0)   // past 08:00, no log
        let day = AdherenceCalculator.days(medicines: [dupRuleMed()], logs: [], now: now, days: 1, calendar: cal).last!
        XCTAssertEqual(day.missed, 1, "a duplicate-rule miss counts once, not twice")
    }

    // MARK: source — draft → rules

    func testEditableDraftDeDupsIdenticalTimes() {
        let t = at(2026, 6, 16, 9, 30)
        let draft = EditableDraft(times: [t, t], source: .manual)
        XCTAssertEqual(draft.doseTimes(calendar: cal).count, 1, "two equal times persist as one rule")
    }

    /// Guard against over-collapsing: distinct times must be preserved.
    func testEditableDraftKeepsDistinctTimes() {
        let draft = EditableDraft(times: [at(2026, 6, 16, 8, 0), at(2026, 6, 16, 20, 0)], source: .manual)
        XCTAssertEqual(draft.doseTimes(calendar: cal).count, 2)
    }
}
