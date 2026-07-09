import XCTest
@testable import Dose

final class AdherenceTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let medID = UUID()

    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }
    private func dailyMed(createdAt: Date = .distantPast) -> MedicineSnapshot {
        MedicineSnapshot(id: medID, name: "X", dosage: nil,
                         rules: [DoseSlotRule(hour: 8, minute: 0, weekdays: [])], createdAt: createdAt)
    }
    private func taken(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 8) -> DoseLogSnapshot {
        DoseLogSnapshot(medicineID: medID, scheduledFor: at(y, mo, d, h, 0), action: .taken, actionedAt: at(y, mo, d, h, 1))
    }
    private func skipped(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 8) -> DoseLogSnapshot {
        DoseLogSnapshot(medicineID: medID, scheduledFor: at(y, mo, d, h, 0), action: .skipped, actionedAt: at(y, mo, d, h, 1))
    }

    // MARK: - Multi-log slots resolve by the LATEST log (the same rule Today's status uses)

    /// Take at 08:01, then "Skip today" at 08:20 — the user corrected themselves. Today's card shows
    /// Skipped (latest log wins); History must agree instead of silently keeping the overridden take.
    /// Pre-fix, dayAdherence checked `.taken` FIRST regardless of order, so the two screens disagreed
    /// about the same slot forever.
    func testTakeThenSkipCountsAsSkippedNotTaken() {
        let now = at(2026, 6, 16, 12, 0)
        let slot = at(2026, 6, 16, 8, 0)
        let logs = [
            DoseLogSnapshot(medicineID: medID, scheduledFor: slot, action: .taken, actionedAt: at(2026, 6, 16, 8, 1)),
            DoseLogSnapshot(medicineID: medID, scheduledFor: slot, action: .skipped, actionedAt: at(2026, 6, 16, 8, 20)),
        ]
        let days = AdherenceCalculator.days(medicines: [dailyMed()], logs: logs, now: now, days: 1, calendar: cal)
        XCTAssertEqual(days.last?.skipped, 1, "the latest action (skip) is the slot's resolution")
        XCTAssertEqual(days.last?.taken, 0, "the overridden take no longer counts")
        XCTAssertEqual(days.last?.missed, 0)
    }

    /// The mirror case: skip first, then take late — the take wins (one slot, one resolution).
    func testSkipThenTakeCountsAsTaken() {
        let now = at(2026, 6, 16, 12, 0)
        let slot = at(2026, 6, 16, 8, 0)
        let logs = [
            DoseLogSnapshot(medicineID: medID, scheduledFor: slot, action: .skipped, actionedAt: at(2026, 6, 16, 8, 5)),
            DoseLogSnapshot(medicineID: medID, scheduledFor: slot, action: .taken, actionedAt: at(2026, 6, 16, 9, 0)),
        ]
        let days = AdherenceCalculator.days(medicines: [dailyMed()], logs: logs, now: now, days: 1, calendar: cal)
        XCTAssertEqual(days.last?.taken, 1)
        XCTAssertEqual(days.last?.skipped, 0)
    }

    /// Orphan slots (no current rule reconstructs them, e.g. after a schedule edit) resolve by the
    /// SAME latest-log rule — pre-fix the orphan loop counted whichever entry came first in the array.
    func testOrphanTakeThenSkipCountsAsSkipped() {
        let now = at(2026, 6, 16, 12, 0)
        let eveningMed = MedicineSnapshot(id: medID, name: "X", dosage: nil,
                                          rules: [DoseSlotRule(hour: 20, minute: 0)])   // 08:00 is an orphan
        let slot = at(2026, 6, 16, 8, 0)
        let logs = [
            DoseLogSnapshot(medicineID: medID, scheduledFor: slot, action: .taken, actionedAt: at(2026, 6, 16, 8, 1)),
            DoseLogSnapshot(medicineID: medID, scheduledFor: slot, action: .skipped, actionedAt: at(2026, 6, 16, 8, 20)),
        ]
        let days = AdherenceCalculator.days(medicines: [eveningMed], logs: logs, now: now, days: 1, calendar: cal)
        XCTAssertEqual(days.last?.skipped, 1, "orphan slot: latest log wins, counted once")
        XCTAssertEqual(days.last?.taken, 0)
    }

    func testAdherenceCountsPastResolvedSlots() {
        let now = at(2026, 6, 16, 12, 0)
        let logs = [taken(2026, 6, 16), taken(2026, 6, 15), taken(2026, 6, 14)]  // 06-13 forgotten
        let days = AdherenceCalculator.days(medicines: [dailyMed()], logs: logs, now: now, days: 4, calendar: cal)
        XCTAssertEqual(days.count, 4)
        XCTAssertEqual(AdherenceCalculator.adherence(days), 0.75, accuracy: 0.001)  // 3 taken / 4 counted
    }

    func testTodayFutureSlotNotCounted() {
        let now = at(2026, 6, 16, 7, 0)   // before the 08:00 dose
        let days = AdherenceCalculator.days(medicines: [dailyMed()], logs: [], now: now, days: 1, calendar: cal)
        XCTAssertEqual(days.last?.counted, 0)   // not yet due → not counted against adherence
    }

    // A medicine added today must NOT show misses on days before it existed.
    func testNoCountedDosesBeforeCreatedAt() {
        let now = at(2026, 6, 16, 12, 0)
        let med = dailyMed(createdAt: at(2026, 6, 16))      // created today (midnight)
        let days = AdherenceCalculator.days(medicines: [med], logs: [], now: now, days: 7, calendar: cal)
        // Only today is on/after createdAt and past its time → exactly 1 counted (not 7), and it's today's.
        XCTAssertEqual(days.reduce(0) { $0 + $1.counted }, 1)
        XCTAssertEqual(days.last?.counted, 1)
        XCTAssertEqual(days.dropLast().reduce(0) { $0 + $1.counted }, 0, "no counted doses before createdAt")
    }

    // MARK: - Item 3: past-due untaken counts as missed (the repeat bug, locked)

    /// THE regression test. A dose only 30 minutes past its time — i.e. still inside the old 60-min
    /// grace window — and untaken must count as a miss. Under the previous grace-based rule this was
    /// excluded (rate 100%, "fake" adherence); now it is missed and lowers the rate.
    func testPastDueUntakenWithinOldGraceCountsAsMissed() {
        let now = at(2026, 6, 16, 8, 30)   // 30 min after the 08:00 dose; OLD grace was 60 min
        let days = AdherenceCalculator.days(medicines: [dailyMed()], logs: [], now: now, days: 1, calendar: cal)
        XCTAssertEqual(days.last?.missed, 1, "a past-its-time untaken dose is missed, grace or not")
        XCTAssertEqual(days.last?.counted, 1)
        XCTAssertEqual(AdherenceCalculator.rate(days), 0.0, "0 taken / 1 counted = 0%, not a fake 100%")
    }

    /// "7-day < 100% AND missed this week ≥ 1" when today's dose is past-due and untaken among an
    /// otherwise perfect week.
    func testTodayPastDueDropsSevenDayBelow100AndCountsMissed() {
        let now = at(2026, 6, 16, 12, 0)                 // today's 08:00 dose is past-due, untaken
        let med = dailyMed(createdAt: at(2026, 6, 9))
        let logs = (10...15).map { taken(2026, 6, $0) }  // 06-10…06-15 taken; today (06-16) untaken
        let last7 = Array(AdherenceCalculator.days(medicines: [med], logs: logs, now: now, days: 7, calendar: cal))
        XCTAssertEqual(AdherenceCalculator.rate(last7)!, 6.0 / 7.0, accuracy: 0.0001)
        XCTAssertLessThan(AdherenceCalculator.rate(last7)!, 1.0, "an untaken past-due dose must drop below 100%")
        XCTAssertGreaterThanOrEqual(AdherenceCalculator.missedCount(last7), 1, "missed-this-week includes it")
    }

    /// An upcoming (time-not-yet-reached) untaken dose does NOT lower the percentage.
    func testUpcomingUntakenDoesNotLowerRate() {
        let now = at(2026, 6, 16, 12, 0)
        // Two daily slots: 08:00 (past, taken) and 20:00 (upcoming, untaken).
        let med = MedicineSnapshot(id: medID, name: "X", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0), DoseSlotRule(hour: 20, minute: 0)],
                                   createdAt: at(2026, 6, 16))
        let days = AdherenceCalculator.days(medicines: [med], logs: [taken(2026, 6, 16, 8)], now: now, days: 1, calendar: cal)
        XCTAssertEqual(days.last?.taken, 1)
        XCTAssertEqual(days.last?.missed, 0, "the 20:00 dose isn't due yet → not missed")
        XCTAssertEqual(days.last?.counted, 1, "only the past 08:00 dose counts")
        XCTAssertEqual(AdherenceCalculator.rate(days), 1.0, "upcoming doses don't lower adherence")
    }

    /// An explicit Skip is neutral — out of BOTH numerator and denominator (same rule as the streak),
    /// and it is not counted as missed.
    func testSkipIsNeutralOutOfNumeratorAndDenominator() {
        let now = at(2026, 6, 16, 12, 0)
        let med = dailyMed(createdAt: at(2026, 6, 15))
        let logs = [taken(2026, 6, 16), skipped(2026, 6, 15)]
        let days = AdherenceCalculator.days(medicines: [med], logs: logs, now: now, days: 2, calendar: cal)
        XCTAssertEqual(days.reduce(0) { $0 + $1.skipped }, 1)
        XCTAssertEqual(days.reduce(0) { $0 + $1.missed }, 0, "a skip is not a miss")
        XCTAssertEqual(days.reduce(0) { $0 + $1.counted }, 1, "the skip is out of the denominator")
        XCTAssertEqual(AdherenceCalculator.rate(days), 1.0, "1 taken / 1 counted; skip neutral")
    }

    /// The chart series and the header percentage come from the SAME source and agree on what counts:
    /// rate == Σtaken / Σcounted, and missed-this-week == Σmissed, over one mixed series.
    func testChartSeriesAndHeaderAgreeOnTheSameSource() {
        let now = at(2026, 6, 16, 12, 0)
        let med = dailyMed(createdAt: at(2026, 6, 10))
        let logs = [taken(2026, 6, 16), taken(2026, 6, 14), skipped(2026, 6, 13)]  // 15,12,11,10 missed
        let series = AdherenceCalculator.days(medicines: [med], logs: logs, now: now, days: 7, calendar: cal)

        let totalTaken = series.reduce(0) { $0 + $1.taken }
        let totalCounted = series.reduce(0) { $0 + $1.counted }
        XCTAssertEqual(AdherenceCalculator.rate(series)!, Double(totalTaken) / Double(totalCounted), accuracy: 1e-9)
        XCTAssertEqual(AdherenceCalculator.missedCount(series), series.reduce(0) { $0 + $1.missed })
        // Concretely: taken 16,14 (2); skipped 13 (neutral); missed 15,12,11,10 (4) → 2 / 6.
        XCTAssertEqual(totalTaken, 2)
        XCTAssertEqual(totalCounted, 6)
        XCTAssertEqual(AdherenceCalculator.missedCount(series), 4)
    }

    // MARK: - Windowing & exclusions

    /// Med created today, 4 doses, 3 taken, 1 past-due untaken → BOTH windows reflect only today
    /// (3/4); prior "No doses" days move neither percentage.
    func testMedCreatedTodayBothWindowsReflectOnlyToday() {
        let now = at(2026, 6, 16, 22, 0)   // all four slots are past their time
        let med = MedicineSnapshot(id: medID, name: "X", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0), DoseSlotRule(hour: 12, minute: 0),
                                           DoseSlotRule(hour: 16, minute: 0), DoseSlotRule(hour: 20, minute: 0)],
                                   createdAt: at(2026, 6, 16))
        let logs = [taken(2026, 6, 16, 8), taken(2026, 6, 16, 12), taken(2026, 6, 16, 16)]  // 20:00 missed

        let last30 = AdherenceCalculator.days(medicines: [med], logs: logs, now: now, days: 30, calendar: cal)
        let last7 = Array(last30.suffix(7))

        XCTAssertEqual(last30.reduce(0) { $0 + $1.counted }, 4)
        XCTAssertEqual(last30.dropLast().reduce(0) { $0 + $1.counted }, 0, "prior 'No doses' days contribute nothing")
        XCTAssertEqual(AdherenceCalculator.rate(last7)!, 0.75, accuracy: 0.0001)
        XCTAssertEqual(AdherenceCalculator.rate(last30)!, 0.75, accuracy: 0.0001)
    }

    /// "No doses" days are neutral — the rate is the true taken/counted (2/3), NOT dragged toward
    /// 100% or 0% by the empty pre-creation days.
    func testNoDoseDaysAreNeutralNotZeroNotHundred() {
        let now = at(2026, 6, 16, 12, 0)
        let med = dailyMed(createdAt: at(2026, 6, 14))   // existed 3 days: 06-14, 06-15, 06-16
        let logs = [taken(2026, 6, 14), taken(2026, 6, 16)]  // 06-15 forgotten
        let last30 = AdherenceCalculator.days(medicines: [med], logs: logs, now: now, days: 30, calendar: cal)
        XCTAssertEqual(AdherenceCalculator.rate(last30)!, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertNotEqual(AdherenceCalculator.rate(last30)!, 29.0 / 30.0, accuracy: 0.01)  // not "empty = 100%"
        XCTAssertNotEqual(AdherenceCalculator.rate(last30)!, 2.0 / 30.0, accuracy: 0.01)   // not "empty = 0%"
    }

    /// 7-day and 30-day are independent windows: when data spans both, they differ.
    func testWindowsDifferWhenDataSpansThem() {
        let now = at(2026, 6, 16, 12, 0)
        let med = dailyMed(createdAt: at(2026, 5, 1))   // exists across the whole 30-day window
        let logs = (10...16).map { taken(2026, 6, $0) }  // only the recent 7 days taken
        let last30 = AdherenceCalculator.days(medicines: [med], logs: logs, now: now, days: 30, calendar: cal)
        let last7 = Array(last30.suffix(7))
        let r7 = AdherenceCalculator.rate(last7)!
        let r30 = AdherenceCalculator.rate(last30)!
        XCTAssertEqual(r7, 1.0, accuracy: 0.0001, "recent week perfect")
        XCTAssertEqual(r30, 7.0 / 30.0, accuracy: 0.0001, "month dragged down by older misses")
        XCTAssertNotEqual(r7, r30, accuracy: 0.05, "the two windows must not coincide when data spans them")
    }

    /// A slot scheduled before the medicine was actually added on the creation day is excluded.
    func testCreationDaySlotBeforeAddTimeExcluded() {
        let now = at(2026, 6, 16, 18, 0)
        let med = MedicineSnapshot(id: medID, name: "X", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0), DoseSlotRule(hour: 16, minute: 0)],
                                   createdAt: at(2026, 6, 16, 14, 0))   // added at 2pm
        let days = AdherenceCalculator.days(medicines: [med], logs: [], now: now, days: 1, calendar: cal)
        // 08:00 < 14:00 → excluded; 16:00 ≥ 14:00 and past its time → the only counted slot (missed).
        XCTAssertEqual(days.last?.counted, 1, "only the after-add 16:00 slot counts")
        XCTAssertEqual(days.last?.missed, 1)
    }

    // MARK: - Item 2: treatment end (post-end days are neutral, never missed)

    /// A finished course keeps its in-window rate and does NOT decay as days pass: post-end days are
    /// out of the window entirely (0 counted), so only the in-course outcomes matter.
    func testFinishedCourseKeepsInWindowRateAndDoesNotDecay() {
        let med = MedicineSnapshot(id: medID, name: "Course", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0)],
                                   createdAt: at(2026, 6, 1), endDate: at(2026, 6, 6))   // 6 in-course days
        let logs = [1, 2, 4, 5, 6].map { taken(2026, 6, $0) }                            // 6/3 missed
        for nowDay in [16, 26] {                                                          // long after the course
            let now = at(2026, 6, nowDay, 12, 0)
            let last30 = AdherenceCalculator.days(medicines: [med], logs: logs, now: now, days: 30, calendar: cal)
            XCTAssertEqual(AdherenceCalculator.rate(last30)!, 5.0 / 6.0, accuracy: 0.0001,
                           "in-window rate, no decay (now=6/\(nowDay))")
            XCTAssertEqual(AdherenceCalculator.missedCount(last30), 1,
                           "only the in-course miss counts — post-end days are not misses (now=6/\(nowDay))")
        }
    }

    /// Today shows no doses for a finished course, but does during it.
    func testTodayExcludesFinishedCourse() {
        let med = MedicineSnapshot(id: medID, name: "Course", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0)],
                                   createdAt: at(2026, 6, 1), endDate: at(2026, 6, 6))
        let after = ExecutionEngine.todaysDoses(medicines: [med], logs: [], now: at(2026, 6, 10, 12, 0), calendar: cal)
        XCTAssertTrue(after.isEmpty, "a finished course shows nothing on Today")
        let during = ExecutionEngine.todaysDoses(medicines: [med], logs: [], now: at(2026, 6, 5, 12, 0), calendar: cal)
        XCTAssertEqual(during.count, 1, "still shows during the course")
    }

    /// Item 4: explicit skips are DISPLAYED (surfaced per-day for the chart) but NOT SCORED — they
    /// stay out of the adherence % and don't break the streak, and they are distinct from misses.
    func testSkipsAreDisplayedButNotScored() {
        let now = at(2026, 6, 16, 23, 0)   // late: today's slots have all passed
        let med = MedicineSnapshot(id: medID, name: "X", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0), DoseSlotRule(hour: 12, minute: 0),
                                           DoseSlotRule(hour: 16, minute: 0)],
                                   createdAt: at(2026, 6, 15))   // exists 6/15 and 6/16
        let takenLogs = [8, 12, 16].map { taken(2026, 6, 15, $0) }   // 6/15 fully taken (baseline)
        let skipLogs = [8, 12, 16].map { skipped(2026, 6, 16, $0) }  // 6/16 all three skipped

        let series = AdherenceCalculator.days(medicines: [med], logs: takenLogs + skipLogs, now: now, days: 7, calendar: cal)
        let today = try! XCTUnwrap(series.last)
        XCTAssertEqual(today.skipped, 3, "3 skips are surfaced for the chart")
        XCTAssertEqual(today.taken, 0)
        XCTAssertEqual(today.missed, 0, "a skip is not a miss — the day is not blank, but not red either")
        XCTAssertEqual(today.counted, 0, "skips are out of the denominator")

        // Not scored: skips don't lower the rate or add misses.
        XCTAssertEqual(AdherenceCalculator.rate(series)!, 1.0, accuracy: 0.0001, "skips don't lower adherence")
        XCTAssertEqual(AdherenceCalculator.missedCount(series), 0)
        XCTAssertEqual(StreakCalculator.currentStreak(medicines: [med], logs: takenLogs + skipLogs, now: now, calendar: cal),
                       2, "skipped days don't break the streak (6/16 + 6/15)")

        // Contrast: leaving those same slots unactioned would tank the numbers — proving skip ≠ miss.
        let unactioned = AdherenceCalculator.days(medicines: [med], logs: takenLogs, now: now, days: 7, calendar: cal)
        XCTAssertEqual(AdherenceCalculator.rate(unactioned)!, 0.5, accuracy: 0.0001)
        XCTAssertEqual(AdherenceCalculator.missedCount(unactioned), 3)
        XCTAssertEqual(StreakCalculator.currentStreak(medicines: [med], logs: takenLogs, now: now, calendar: cal), 0)
    }

    /// Item 1 (FAIL-FIRST): a med created THIS AFTERNOON with a dose taken at THIS MORNING's 08:00 slot
    /// must count as 1 taken / 100% — not 0. The old `guard slot >= createdAt` (applied before the
    /// taken check) dropped the real take, under-counting in BOTH the report and the in-app History.
    func testTakeAtSlotBeforeCreatedAtStillCounts() {
        let createdAt = at(2026, 6, 16, 14, 0)         // created 2pm today
        let now = at(2026, 6, 16, 18, 0)
        let med = MedicineSnapshot(id: medID, name: "Created Today", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0)], createdAt: createdAt)
        let logs = [taken(2026, 6, 16, 8)]             // taken at 08:00, before the 2pm creation
        let days = AdherenceCalculator.days(medicines: [med], logs: logs, now: now, days: 1, calendar: cal)
        XCTAssertEqual(days.last?.taken, 1, "a taken dose counts even if its slot precedes createdAt")
        XCTAssertEqual(days.last?.missed, 0)
        XCTAssertEqual(AdherenceCalculator.rate(days), 1.0, "1 of 1 taken = 100%, not 0")
    }

    /// Item 1: a `.taken` log whose `scheduledFor` no current rule reconstructs (e.g. schedule edited
    /// after the dose) is still counted — adherence is log-driven for resolved actions.
    func testOrphanTakeLogStillCounts() {
        let now = at(2026, 6, 16, 18, 0)
        let med = MedicineSnapshot(id: medID, name: "X", dosage: nil,
                                   rules: [DoseSlotRule(hour: 9, minute: 0)],   // rule says 09:00
                                   createdAt: at(2026, 6, 1))
        let logs = [taken(2026, 6, 16, 8)]             // but the dose was taken/logged at 08:00
        let days = AdherenceCalculator.days(medicines: [med], logs: logs, now: now, days: 1, calendar: cal)
        XCTAssertEqual(days.last?.taken, 1, "an orphan take (no matching reconstructed slot) still counts")
    }

    /// An all-empty window (brand-new med, nothing due yet) has no data → rate is nil (render a dash).
    func testEmptyWindowRateIsNil() {
        let now = at(2026, 6, 16, 7, 0)   // before today's 08:00 dose, med created today
        let med = dailyMed(createdAt: at(2026, 6, 16))
        let days = AdherenceCalculator.days(medicines: [med], logs: [], now: now, days: 7, calendar: cal)
        XCTAssertNil(AdherenceCalculator.rate(days), "no data → neutral, not a percentage")
    }

    /// PARITY: the History event log ("Missed" filter) and the Week "missed this week" count read the
    /// SAME source — `missedEvents(...).count` equals `missedCount(days(...))` for the same window, and
    /// the events are exactly the past-due-untaken slots (skips and takes excluded), oldest → newest.
    func testMissedEventsMatchMissedCountForTheSameWindow() {
        let now = at(2026, 6, 16, 12, 0)
        let med = dailyMed(createdAt: at(2026, 6, 10))
        let logs = [taken(2026, 6, 16), taken(2026, 6, 14), skipped(2026, 6, 13)]  // 15,12,11,10 missed
        let from = at(2026, 6, 10), to = at(2026, 6, 16)

        let days = AdherenceCalculator.days(medicines: [med], logs: logs, from: from, to: to, now: now, calendar: cal)
        let events = AdherenceCalculator.missedEvents(medicines: [med], logs: logs, from: from, to: to, now: now, calendar: cal)

        XCTAssertEqual(events.count, AdherenceCalculator.missedCount(days),
                       "missedEvents count equals the missed count for the same window")
        XCTAssertEqual(events.count, 4, "concretely 06-10, 06-11, 06-12, 06-15 are missed (13 skipped, 14 & 16 taken)")
        XCTAssertEqual(events.map { cal.component(.day, from: $0.scheduledFor) }, [10, 11, 12, 15],
                       "the missed slots are exactly the untaken past-due days, oldest → newest")
        XCTAssertTrue(events.allSatisfy { $0.medicineID == medID }, "every event is a real slot of the medicine")
    }

    /// An actively-snoozed dose is DEFERRED — neither taken nor missed — until its snooze window elapses,
    /// matching Today's `.snoozed` status. FAIL-BEFORE: adherence counted it missed at `now > slot`,
    /// so Week/History listed a still-snoozed dose under "Missed". PASS-AFTER: excluded while snoozed,
    /// missed once the window passes; `missedEvents` and `missedCount` stay in parity throughout.
    func testSnoozedDoseNotMissedWhileWithinSnoozeWindow() {
        let slot = at(2026, 6, 16, 8, 0)
        let snoozedAt = at(2026, 6, 16, 8, 5)                 // snoozed 60 min → until 09:05
        let med = dailyMed(createdAt: at(2026, 6, 10))
        let logs = [DoseLogSnapshot(medicineID: medID, scheduledFor: slot, action: .snoozed,
                                    actionedAt: snoozedAt, snoozeMinutes: 60)]

        // 08:30 — within the snooze window → NOT missed, NOT counted; missedEvents excludes it.
        let midNow = at(2026, 6, 16, 8, 30)
        let within = AdherenceCalculator.days(medicines: [med], logs: logs, now: midNow, days: 1, calendar: cal)
        XCTAssertEqual(within.last?.missed, 0, "a dose still within its snooze window is not missed")
        XCTAssertEqual(within.last?.counted, 0, "…and not yet counted against adherence")
        XCTAssertTrue(AdherenceCalculator.missedEvents(medicines: [med], logs: logs, from: slot, to: midNow, now: midNow, calendar: cal).isEmpty,
                      "missedEvents also excludes an in-window snooze")

        // 10:00 — past 09:05 with no further action → missed; parity holds.
        let lateNow = at(2026, 6, 16, 10, 0)
        let after = AdherenceCalculator.days(medicines: [med], logs: logs, now: lateNow, days: 1, calendar: cal)
        XCTAssertEqual(after.last?.missed, 1, "once the snooze elapses with no action, it's missed")
        let events = AdherenceCalculator.missedEvents(medicines: [med], logs: logs, from: slot, to: lateNow, now: lateNow, calendar: cal)
        XCTAssertEqual(events.count, AdherenceCalculator.missedCount(after), "missedEvents == missedCount with a snoozed slot")
    }

    /// Day-bucketing is DST-safe: with a DST-observing calendar, a late-evening daily dose across the
    /// spring-forward AND fall-back days buckets to exactly one slot per LOCAL day (never 0 or 2), and
    /// missedEvents.count == missedCount holds across the boundary. (Real notification DELIVERY on the
    /// transition day is device-only; this proves the bucketing arithmetic every screen shares.)
    func testDayBucketingIsDSTSafe() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        func nyDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
            ny.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
        }
        let id = UUID()
        let rule = DoseSlotRule(hour: 23, minute: 30)   // 23:30 local, daily

        // Spring-forward 2026-03-08 (02:00→03:00). Window 03-06…03-10, all past, no logs → all missed.
        let sfMed = MedicineSnapshot(id: id, name: "X", dosage: nil, rules: [rule], createdAt: nyDate(2026, 3, 1))
        let sfDays = AdherenceCalculator.days(medicines: [sfMed], logs: [], from: nyDate(2026, 3, 6),
                                              to: nyDate(2026, 3, 10, 23, 59), now: nyDate(2026, 3, 11, 12), calendar: ny)
        XCTAssertEqual(sfDays.count, 5, "one bucket per local day across spring-forward")
        XCTAssertTrue(sfDays.allSatisfy { $0.missed == 1 }, "each local day has exactly one 23:30 dose (not 0 or 2)")
        let sfEvents = AdherenceCalculator.missedEvents(medicines: [sfMed], logs: [], from: nyDate(2026, 3, 6),
                                                        to: nyDate(2026, 3, 10, 23, 59), now: nyDate(2026, 3, 11, 12), calendar: ny)
        XCTAssertEqual(sfEvents.count, AdherenceCalculator.missedCount(sfDays), "parity holds across spring-forward")

        // Fall-back 2026-11-01 (02:00→01:00).
        let fbMed = MedicineSnapshot(id: id, name: "X", dosage: nil, rules: [rule], createdAt: nyDate(2026, 10, 1))
        let fbDays = AdherenceCalculator.days(medicines: [fbMed], logs: [], from: nyDate(2026, 10, 30),
                                              to: nyDate(2026, 11, 3, 23, 59), now: nyDate(2026, 11, 4, 12), calendar: ny)
        XCTAssertEqual(fbDays.count, 5, "one bucket per local day across fall-back")
        XCTAssertTrue(fbDays.allSatisfy { $0.missed == 1 }, "each local day has exactly one 23:30 dose across fall-back")
    }
}
