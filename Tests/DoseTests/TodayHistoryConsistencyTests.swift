import XCTest
@testable import Dose

/// Today and History must never disagree about whether a dose was missed. Both derive "missed" from the
/// SAME medicine-lifetime rule (`ExecutionEngine.isWithinLifetime`, floored at the exact `createdAt`
/// instant). The reported bug: a med added at 10:00 with an 08:00 dose showed "Missed" on Today (which
/// used a *day-level* createdAt floor) while History correctly counted 0 — an impossible pair.
final class TodayHistoryConsistencyTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let medID = UUID()

    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }
    private func dailyMed(createdAt: Date) -> MedicineSnapshot {
        MedicineSnapshot(id: medID, name: "Ibuprofen", dosage: nil,
                         rules: [DoseSlotRule(hour: 8, minute: 0)], createdAt: createdAt)
    }

    /// A genuinely past-due, un-acted dose (scheduled AFTER the med existed) is Missed on Today AND
    /// counted exactly once by History for that day — and History does NOT say "Nothing missed". This is
    /// the positive invariant the goal asks for; it must hold before and after the fix (regression guard).
    func testPastDueDoseIsMissedOnTodayAndCountedByHistory() {
        let now = at(2026, 6, 16, 12, 0)                     // well past 08:00 + 60-min grace
        let med = dailyMed(createdAt: at(2026, 6, 16, 6, 0))  // added 06:00, BEFORE the 08:00 dose → legit
        let today = ExecutionEngine.todaysDoses(medicines: [med], logs: [], now: now, calendar: cal)
        let series = AdherenceCalculator.days(medicines: [med], logs: [], now: now, days: 7, calendar: cal)

        // Today: the 08:00 dose is Missed.
        XCTAssertEqual(today.count, 1)
        XCTAssertEqual(today.first?.status, .missed, "past-grace, un-acted → Missed on Today")

        // History: exactly one missed for that day; the week card is NOT 'Nothing missed'.
        XCTAssertEqual(series.last?.missed, 1, "History counts exactly one missed for today")
        XCTAssertEqual(AdherenceCalculator.missedCount(series), 1)
        XCTAssertGreaterThan(AdherenceCalculator.missedCount(series), 0,
                             "MissedThisWeekCard shows '1 missed', never 'Nothing missed'")

        // The invariant: the two screens agree.
        let todayHasMiss = today.contains { $0.status == .missed }
        XCTAssertEqual(todayHasMiss, AdherenceCalculator.missedCount(series) > 0,
                       "Today and History must agree on whether a dose was missed")
    }

    /// THE reported bug (fail-before / pass-after): a dose scheduled BEFORE the med was added on the
    /// creation day was never actionable, so it must NOT be 'Missed' on Today — matching History, which
    /// already excludes it. Pre-fix, Today used a day-level createdAt floor and showed a phantom Missed
    /// while History showed "Nothing missed" — exactly the reported contradiction.
    func testPreCreationDoseIsNotMissedOnEitherScreen() {
        let now = at(2026, 6, 16, 12, 0)
        let med = dailyMed(createdAt: at(2026, 6, 16, 10, 0))  // added 10:00, AFTER the 08:00 dose
        let today = ExecutionEngine.todaysDoses(medicines: [med], logs: [], now: now, calendar: cal)
        let series = AdherenceCalculator.days(medicines: [med], logs: [], now: now, days: 7, calendar: cal)

        let todayHasMiss = today.contains { $0.status == .missed }
        let historyMissed = AdherenceCalculator.missedCount(series)

        // The core invariant that was violated in the report: the two must agree.
        XCTAssertEqual(todayHasMiss, historyMissed > 0,
                       "Today and History must agree — a pre-creation dose is missed on neither")
        // And the correct resolution: neither screen treats it as missed.
        XCTAssertFalse(todayHasMiss, "a dose scheduled before the med was added is not a miss on Today")
        XCTAssertEqual(historyMissed, 0, "…and History agrees (Nothing missed)")

        // Crucially, the med is NOT hidden — a freshly-added medicine still appears on Today so the user
        // can act on today's dose; it just shows as takeable (.due), never a phantom "Missed".
        XCTAssertEqual(today.count, 1, "the freshly-added med still appears on Today (not hidden)")
        XCTAssertEqual(today.first?.status, .due, "its pre-creation dose stays takeable, not 'Missed'")
    }

    /// Multi-log slots: Take at 08:01 then "Skip today" at 08:20. Today resolves by the LATEST log
    /// (Skipped); History must resolve the SAME slot the SAME way — pre-fix it checked `.taken` first
    /// and the two screens permanently disagreed about the same dose.
    func testTakeThenSkipAgreesOnBothScreens() {
        let now = at(2026, 6, 16, 12, 0)
        let med = dailyMed(createdAt: at(2026, 6, 16, 6, 0))
        let slot = at(2026, 6, 16, 8, 0)
        let logs = [
            DoseLogSnapshot(medicineID: medID, scheduledFor: slot, action: .taken, actionedAt: at(2026, 6, 16, 8, 1)),
            DoseLogSnapshot(medicineID: medID, scheduledFor: slot, action: .skipped, actionedAt: at(2026, 6, 16, 8, 20)),
        ]
        let today = ExecutionEngine.todaysDoses(medicines: [med], logs: logs, now: now, calendar: cal)
        let series = AdherenceCalculator.days(medicines: [med], logs: logs, now: now, days: 7, calendar: cal)

        XCTAssertEqual(today.first?.status, .skipped, "Today: the latest log wins")
        XCTAssertEqual(series.last?.skipped, 1, "History resolves the same slot the same way")
        XCTAssertEqual(series.last?.taken, 0, "History must not ALSO count the overridden take")
        XCTAssertEqual(AdherenceCalculator.missedCount(series), 0, "and it is not a miss on either screen")
    }
}
