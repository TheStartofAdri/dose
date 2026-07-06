import XCTest
@testable import Dose

final class StreakTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private let medID = UUID()

    private func dayStart(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    private func dailyMed() -> MedicineSnapshot {
        MedicineSnapshot(id: medID, name: "Vitamin D", dosage: nil,
                         rules: [DoseSlotRule(hour: 8, minute: 0, weekdays: [])])
    }

    /// A taken log at 08:00 on the given day.
    private func taken(_ y: Int, _ mo: Int, _ d: Int) -> DoseLogSnapshot {
        DoseLogSnapshot(medicineID: medID, scheduledFor: dayStart(y, mo, d, 8, 0),
                        action: .taken, actionedAt: dayStart(y, mo, d, 8, 1))
    }

    private func skipped(_ y: Int, _ mo: Int, _ d: Int) -> DoseLogSnapshot {
        DoseLogSnapshot(medicineID: medID, scheduledFor: dayStart(y, mo, d, 8, 0),
                        action: .skipped, actionedAt: dayStart(y, mo, d, 8, 1))
    }

    private func streak(now: Date, logs: [DoseLogSnapshot], medicines: [MedicineSnapshot]? = nil) -> Int {
        StreakCalculator.currentStreak(medicines: medicines ?? [dailyMed()], logs: logs, now: now, calendar: cal)
    }

    func testConsecutiveTakenDaysExtendStreak() {
        // Today + two prior days taken; the day before that is a forgotten miss → streak stops at 3.
        let now = dayStart(2026, 6, 16, 12, 0)
        let logs = [taken(2026, 6, 16), taken(2026, 6, 15), taken(2026, 6, 14)]
        XCTAssertEqual(streak(now: now, logs: logs), 3)
    }

    func testForgottenDoseBreaksStreak() {
        // 06-14 has a scheduled dose, no log, grace long past → breaks. Streak = 16,15 = 2.
        let now = dayStart(2026, 6, 16, 12, 0)
        let logs = [taken(2026, 6, 16), taken(2026, 6, 15)]
        XCTAssertEqual(streak(now: now, logs: logs), 2)
    }

    func testExplicitSkipIsNeutral() {
        // 06-15 is an explicit skip — must NOT break (would be 1 if it did). 06-13 forgotten breaks.
        let now = dayStart(2026, 6, 16, 12, 0)
        let logs = [taken(2026, 6, 16), skipped(2026, 6, 15), taken(2026, 6, 14)]
        XCTAssertEqual(streak(now: now, logs: logs), 3)
    }

    func testTodayInProgressDoesNotBreakStreak() {
        // 07:00 — today's 08:00 dose is still upcoming (not past grace), so today doesn't break.
        let now = dayStart(2026, 6, 16, 7, 0)
        let logs = [taken(2026, 6, 15), taken(2026, 6, 14)]   // no log yet today
        XCTAssertEqual(streak(now: now, logs: logs), 3)        // today + 15 + 14
    }

    func testForgottenDoseTodayPastGraceBreaksStreak() {
        // Contrast: 09:30 today, today's 08:00 dose forgotten past grace → today breaks → 0.
        let now = dayStart(2026, 6, 16, 9, 30)
        let logs = [taken(2026, 6, 15), taken(2026, 6, 14)]
        XCTAssertEqual(streak(now: now, logs: logs), 0)
    }

    func testZeroScheduledDoseDayIsNeutralPassThrough() {
        // Rule fires only on today's weekday and the day-before-yesterday's weekday, leaving the
        // intervening day with no scheduled dose. The empty day must not break the chain.
        let now = dayStart(2026, 6, 16, 12, 0)
        let wToday = cal.component(.weekday, from: now)
        let wMinus2 = cal.component(.weekday, from: cal.date(byAdding: .day, value: -2, to: now)!)
        let med = MedicineSnapshot(id: medID, name: "X", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0, weekdays: [wToday, wMinus2])])
        let logs = [taken(2026, 6, 16), taken(2026, 6, 14)]   // 06-15 is the empty (neutral) day
        // Counts the two scheduled-and-taken days; the empty day passes through; day-7 (same
        // weekday as today) has an unresolved slot → breaks.
        XCTAssertEqual(streak(now: now, logs: logs, medicines: [med]), 2)
    }

    func testNoMedicinesIsZero() {
        XCTAssertEqual(streak(now: dayStart(2026, 6, 16, 12, 0), logs: [], medicines: []), 0)
    }

    // Item 1: a medicine added today injects no pre-creation misses, so it can't destroy an
    // existing streak from an older medicine.
    func testNewMedicineDoesNotBreakOldStreak() {
        let now = dayStart(2026, 6, 16, 12, 0)
        let oldID = UUID(), newID = UUID()
        let medOld = MedicineSnapshot(id: oldID, name: "Old", dosage: nil,
                                      rules: [DoseSlotRule(hour: 8, minute: 0)],
                                      createdAt: dayStart(2026, 6, 6))     // 10 days ago
        let medNew = MedicineSnapshot(id: newID, name: "New", dosage: nil,
                                      rules: [DoseSlotRule(hour: 9, minute: 0)],
                                      createdAt: dayStart(2026, 6, 16))    // today

        var logs: [DoseLogSnapshot] = []
        for d in 6...16 {   // medOld taken every day 06-06 … 06-16 at 08:00
            logs.append(DoseLogSnapshot(medicineID: oldID, scheduledFor: dayStart(2026, 6, d, 8, 0),
                                        action: .taken, actionedAt: dayStart(2026, 6, d, 8, 1)))
        }
        logs.append(DoseLogSnapshot(medicineID: newID, scheduledFor: dayStart(2026, 6, 16, 9, 0),
                                    action: .taken, actionedAt: dayStart(2026, 6, 16, 9, 1)))

        // 11 consecutive no-miss days (06-16 … 06-06). Without the floor, medNew's absent 09:00 on
        // days before today would inject misses and collapse the streak to 1.
        XCTAssertEqual(StreakCalculator.currentStreak(medicines: [medOld, medNew], logs: logs, now: now, calendar: cal), 11)
    }

    // Item 3 (consistency): a med added this afternoon with a *morning* dose must not break the
    // streak with a phantom miss for a slot that was never actionable today.
    func testCreationDayMorningSlotDoesNotBreakStreak() {
        let now = dayStart(2026, 6, 16, 18, 0)
        let oldID = UUID(), newID = UUID()
        let medOld = MedicineSnapshot(id: oldID, name: "Old", dosage: nil,
                                      rules: [DoseSlotRule(hour: 8, minute: 0)],
                                      createdAt: dayStart(2026, 6, 6))          // 10 days ago
        let medNew = MedicineSnapshot(id: newID, name: "New", dosage: nil,
                                      rules: [DoseSlotRule(hour: 8, minute: 0)],
                                      createdAt: dayStart(2026, 6, 16, 14, 0))  // added at 2pm today

        // medOld taken every day 06-06 … 06-16 at 08:00. medNew has NO log (its 08:00 today was
        // before it was even added at 14:00, so it isn't a miss).
        var logs: [DoseLogSnapshot] = []
        for d in 6...16 {
            logs.append(DoseLogSnapshot(medicineID: oldID, scheduledFor: dayStart(2026, 6, d, 8, 0),
                                        action: .taken, actionedAt: dayStart(2026, 6, d, 8, 1)))
        }
        // Without the slot-level floor, medNew's unresolved 08:00 today would break the streak → 0.
        XCTAssertEqual(StreakCalculator.currentStreak(medicines: [medOld, medNew], logs: logs, now: now, calendar: cal), 11)
    }

    // Item 2: a finished course must not break the streak with post-end "misses".
    func testFinishedCourseDoesNotBreakStreak() {
        let now = dayStart(2026, 6, 16, 12, 0)
        let med = MedicineSnapshot(id: medID, name: "Course", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0)],
                                   createdAt: dayStart(2026, 6, 7), endDate: dayStart(2026, 6, 13))
        let logs = (7...13).map { taken(2026, 6, $0) }   // every in-course day taken; 6/14–6/16 are post-end
        // Post-end days (6/14, 6/15, 6/16) have no scheduled slots → neutral. Without the end floor
        // they'd be untaken past-due misses and collapse the streak to 0.
        XCTAssertEqual(streak(now: now, logs: logs, medicines: [med]), 7)
    }
}
