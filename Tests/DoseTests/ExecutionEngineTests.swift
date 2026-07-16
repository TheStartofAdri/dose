import XCTest
@testable import Dose

final class ExecutionEngineTests: XCTestCase {
    // Deterministic calendar/clock — UTC avoids DST/locale flakiness.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private let medID = UUID()

    private func dailyMed(hour: Int = 8, minute: Int = 0) -> MedicineSnapshot {
        MedicineSnapshot(id: medID, name: "Vitamin D", dosage: "1000 IU",
                         rules: [DoseSlotRule(hour: hour, minute: minute, weekdays: [])])
    }

    private func single(_ now: Date, logs: [DoseLogSnapshot] = []) -> TodayDose {
        let doses = ExecutionEngine.todaysDoses(medicines: [dailyMed()], logs: logs, now: now, calendar: cal)
        return doses[0]
    }

    func testUpcomingBeforeDue() {
        XCTAssertEqual(single(date(2026, 6, 16, 7, 0)).status, .upcoming)
    }

    func testDueWithinGrace() {
        XCTAssertEqual(single(date(2026, 6, 16, 8, 30)).status, .due)
    }

    func testDueExactlyAtScheduledTime() {
        XCTAssertEqual(single(date(2026, 6, 16, 8, 0)).status, .due)
    }

    func testStillDueAtGraceBoundary() {
        // 08:00 + 60 min grace = 09:00 → still due (inclusive boundary).
        XCTAssertEqual(single(date(2026, 6, 16, 9, 0)).status, .due)
    }

    func testMissedJustPastGrace() {
        XCTAssertEqual(single(date(2026, 6, 16, 9, 1)).status, .missed)
    }

    func testTakenRegardlessOfTime() {
        let log = DoseLogSnapshot(medicineID: medID, scheduledFor: date(2026, 6, 16, 8, 0),
                                  action: .taken, actionedAt: date(2026, 6, 16, 8, 5))
        XCTAssertEqual(single(date(2026, 6, 16, 23, 0), logs: [log]).status, .taken)
    }

    func testExplicitSkipShowsSkipped() {
        let log = DoseLogSnapshot(medicineID: medID, scheduledFor: date(2026, 6, 16, 8, 0),
                                  action: .skipped, actionedAt: date(2026, 6, 16, 8, 5))
        XCTAssertEqual(single(date(2026, 6, 16, 12, 0), logs: [log]).status, .skipped)
    }

    func testSnoozedShowsSnoozedWithNewTime() {
        let snoozedAt = date(2026, 6, 16, 8, 5)
        let log = DoseLogSnapshot(medicineID: medID, scheduledFor: date(2026, 6, 16, 8, 0),
                                  action: .snoozed, actionedAt: snoozedAt)
        let dose = single(date(2026, 6, 16, 8, 10), logs: [log])
        XCTAssertEqual(dose.status, .snoozed)
        XCTAssertEqual(dose.snoozedUntil, snoozedAt.addingTimeInterval(ExecutionEngine.snoozeInterval))
    }

    func testSnoozeElapsedBecomesDueThenMissed() {
        let snoozedAt = date(2026, 6, 16, 8, 5)   // snooze until 08:15
        let log = DoseLogSnapshot(medicineID: medID, scheduledFor: date(2026, 6, 16, 8, 0),
                                  action: .snoozed, actionedAt: snoozedAt)
        // 08:20: snooze (08:15) elapsed, within grace of 08:15 → due
        XCTAssertEqual(single(date(2026, 6, 16, 8, 20), logs: [log]).status, .due)
        // 09:30: past 08:15 + 60 min → missed
        XCTAssertEqual(single(date(2026, 6, 16, 9, 30), logs: [log]).status, .missed)
    }

    /// A variable snooze (from the in-app action sheet) keeps the dose snoozed for the CHOSEN length,
    /// not the default 10 min. FAIL-BEFORE: with snoozeMinutes ignored, a 30-min snooze would elapse at
    /// +10 and read `.due` at +20; PASS-AFTER: it stays snoozed to actionedAt + 30 min.
    func testVariableSnoozeHonorsChosenMinutes() {
        let snoozedAt = date(2026, 6, 16, 8, 5)
        let log = DoseLogSnapshot(medicineID: medID, scheduledFor: date(2026, 6, 16, 8, 0),
                                  action: .snoozed, actionedAt: snoozedAt, snoozeMinutes: 30)
        // +20 min (08:25): a default 10-min snooze would have elapsed, but a 30-min one is still snoozed.
        let dose = single(date(2026, 6, 16, 8, 25), logs: [log])
        XCTAssertEqual(dose.status, .snoozed, "a 30-min snooze is still snoozed at +20 min")
        XCTAssertEqual(dose.snoozedUntil, snoozedAt.addingTimeInterval(30 * 60), "snoozed-until is actionedAt + 30 min")
        // 08:40: past the chosen 30 min (08:35) but within grace of it → due.
        XCTAssertEqual(single(date(2026, 6, 16, 8, 40), logs: [log]).status, .due)
    }

    func testLatestLogWinsTakenAfterSnooze() {
        let scheduled = date(2026, 6, 16, 8, 0)
        let logs = [
            DoseLogSnapshot(medicineID: medID, scheduledFor: scheduled, action: .snoozed, actionedAt: date(2026, 6, 16, 8, 5)),
            DoseLogSnapshot(medicineID: medID, scheduledFor: scheduled, action: .taken, actionedAt: date(2026, 6, 16, 8, 12)),
        ]
        XCTAssertEqual(single(date(2026, 6, 16, 9, 0), logs: logs).status, .taken)
    }

    /// S4: a `.taken` is terminal — a LATER `.snoozed` for the same slot must not reopen it and erase
    /// the take. FAIL-BEFORE: strict latest-wins let the later snooze win, so the slot read `.due`/
    /// `.missed` again. PASS-AFTER: a terminal action settles the slot regardless of a later snooze.
    func testLaterSnoozeDoesNotEraseAnEarlierTake() {
        let scheduled = date(2026, 6, 16, 8, 0)
        let logs = [
            DoseLogSnapshot(medicineID: medID, scheduledFor: scheduled, action: .taken, actionedAt: date(2026, 6, 16, 8, 12)),
            DoseLogSnapshot(medicineID: medID, scheduledFor: scheduled, action: .snoozed, actionedAt: date(2026, 6, 16, 8, 20)),
        ]
        XCTAssertEqual(single(date(2026, 6, 16, 9, 0), logs: logs).status, .taken,
                       "a take stays taken even if a snooze was logged for the same slot afterwards")
    }

    /// S3: two logs sharing an identical `actionedAt` must resolve deterministically (not by array
    /// order), so Today and History — which receive logs in different orderings — always agree.
    func testEqualActionedAtResolvesDeterministically() {
        let scheduled = date(2026, 6, 16, 8, 0)
        let at = date(2026, 6, 16, 8, 5)
        let taken = DoseLogSnapshot(medicineID: medID, scheduledFor: scheduled, action: .taken, actionedAt: at)
        let skipped = DoseLogSnapshot(medicineID: medID, scheduledFor: scheduled, action: .skipped, actionedAt: at)
        let a = ExecutionEngine.latestLog(medicineID: medID, scheduledFor: scheduled, in: [taken, skipped])
        let b = ExecutionEngine.latestLog(medicineID: medID, scheduledFor: scheduled, in: [skipped, taken])
        XCTAssertEqual(a?.action, b?.action, "resolution is independent of log array order")
    }

    func testWeekdayRuleProducesNoSlotOnOffDays() {
        // Rule only on the weekday *after* our test day → no slot today.
        let day = date(2026, 6, 16, 12, 0)
        let offWeekday = (cal.component(.weekday, from: day) % 7) + 1
        let med = MedicineSnapshot(id: medID, name: "X", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0, weekdays: [offWeekday])])
        XCTAssertTrue(ExecutionEngine.todaysDoses(medicines: [med], logs: [], now: day, calendar: cal).isEmpty)
    }

    func testDosesSortedByTime() {
        let med = MedicineSnapshot(id: medID, name: "X", dosage: nil, rules: [
            DoseSlotRule(hour: 20, minute: 0, weekdays: []),
            DoseSlotRule(hour: 8, minute: 0, weekdays: []),
        ])
        let doses = ExecutionEngine.todaysDoses(medicines: [med], logs: [], now: date(2026, 6, 16, 7, 0), calendar: cal)
        XCTAssertEqual(doses.map { cal.component(.hour, from: $0.scheduledFor) }, [8, 20])
    }

    // MARK: - Grace across the midnight boundary (P2 #5)

    private func lateMed(createdAt: Date = .distantPast, endDate: Date? = nil) -> MedicineSnapshot {
        MedicineSnapshot(id: medID, name: "Night pill", dosage: nil,
                         rules: [DoseSlotRule(hour: 23, minute: 30, weekdays: [])],
                         createdAt: createdAt, endDate: endDate)
    }
    private func carriedFromJun16(_ doses: [TodayDose]) -> TodayDose? {
        doses.first { cal.isDate($0.scheduledFor, inSameDayAs: date(2026, 6, 16)) }
    }

    /// A 23:30 dose is still within its 60-min grace at 00:15 the next day, so it must stay takeable on
    /// Today across the midnight rollover — not vanish. Fail-before: `todaysDoses` projected only `now`'s
    /// calendar day, so the previous night's slot disappeared while adherence still counted it missed at 00:30.
    func testLateDoseStillDueAfterMidnight() {
        let doses = ExecutionEngine.todaysDoses(medicines: [lateMed()], logs: [],
                                                now: date(2026, 6, 17, 0, 15), calendar: cal)
        let carried = carriedFromJun16(doses)
        XCTAssertEqual(carried?.scheduledFor, date(2026, 6, 16, 23, 30), "the previous night's dose is surfaced")
        XCTAssertEqual(carried?.status, .due, "still within its grace window → takeable, not missed/hidden")
    }

    /// Once its grace has fully elapsed (00:31, past 23:30 + 60 min), the late dose drops off Today — it's
    /// now genuinely missed and belongs to History, not carried forward indefinitely.
    func testLateDoseGoneOnceGraceElapsed() {
        let doses = ExecutionEngine.todaysDoses(medicines: [lateMed()], logs: [],
                                                now: date(2026, 6, 17, 0, 31), calendar: cal)
        XCTAssertNil(carriedFromJun16(doses), "past grace, yesterday's missed dose is not carried into Today")
    }

    /// A taken late dose is settled — it must NOT reappear on Today after midnight.
    func testSettledLateDoseNotCarried() {
        let taken = DoseLogSnapshot(medicineID: medID, scheduledFor: date(2026, 6, 16, 23, 30),
                                    action: .taken, actionedAt: date(2026, 6, 16, 23, 40))
        let doses = ExecutionEngine.todaysDoses(medicines: [lateMed()], logs: [taken],
                                                now: date(2026, 6, 17, 0, 15), calendar: cal)
        XCTAssertNil(carriedFromJun16(doses), "a taken late dose is settled and doesn't carry into the next day")
    }

    /// A pre-lifetime phantom must NOT carry: a med created at Jun 16 23:45 has a 23:30 slot that day which
    /// was never actionable (`canBeMissed == false` → perpetually `.due`). Carrying it would pin a dose to
    /// Today forever. Guard that the midnight carryover excludes it.
    func testPreLifetimePhantomNotCarried() {
        let med = lateMed(createdAt: date(2026, 6, 16, 23, 45))    // created AFTER the 23:30 slot
        let doses = ExecutionEngine.todaysDoses(medicines: [med], logs: [],
                                                now: date(2026, 6, 17, 0, 15), calendar: cal)
        XCTAssertNil(carriedFromJun16(doses), "a slot before the med's creation instant is never carried forward")
    }
}
