import XCTest
@testable import Dose

/// The notification PLAN: every dose occurrence in the horizon is a per-occurrence one-shot (so it's
/// individually cancellable), allocated on-time → escalation → lead-time within the 64 cap, and a
/// taken/skipped dose is never (re)scheduled. (Cancellation wiring is in NotificationCancellationTests.)
final class NotificationBudgetTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let now = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 6, minute: 0))!
    }()

    private func dailyMeds(_ n: Int, hour: Int = 8) -> [MedicineSnapshot] {
        (0..<n).map { i in
            MedicineSnapshot(id: UUID(), name: "Med \(i)", dosage: nil,
                             rules: [DoseSlotRule(hour: hour, minute: i % 60)])
        }
    }
    private func plan(_ meds: [MedicineSnapshot], logs: [DoseLogSnapshot] = [],
                      escalation: Bool = false, budget: Int = NotificationPlanner.maxPending) -> NotificationPlan {
        NotificationPlanner.plan(medicines: meds, logs: logs, now: now, escalationEnabled: escalation,
                                 budget: budget, calendar: cal)
    }
    /// Expected on-time occurrences for a daily rule across the default horizon (mirrors the planner).
    private func expectedDailyOccurrences(hour: Int, minute: Int = 0,
                                          end: Date? = nil) -> [Date] {
        let horizon = end ?? now.addingTimeInterval(NotificationPlanner.defaultWindow)
        var result: [Date] = []
        var day = cal.startOfDay(for: now)
        while day <= horizon {
            if let occ = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day), occ >= now, occ <= horizon {
                result.append(occ)
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    // MARK: - Coverage (exact set, not "≥1")

    func testDailyMedSchedulesOnTimeForEveryDayInHorizon() {
        let p = plan(dailyMeds(1, hour: 8))
        let expected = expectedDailyOccurrences(hour: 8)
        XCTAssertGreaterThanOrEqual(expected.count, 7, "a daily med spans ~7 days in the horizon")
        XCTAssertEqual(p.onTime.count, expected.count, "one on-time reminder per day — exact, not ≥1")
        XCTAssertEqual(Set(p.onTime.map { $0.scheduledFor }), Set(expected))
        XCTAssertTrue(p.onTime.allSatisfy { cal.component(.hour, from: $0.fireDate) == 8 }, "at the right time")
        XCTAssertTrue(p.onTime.allSatisfy { $0.fireDate == $0.scheduledFor && !$0.isEscalation && $0.leadMinutes == nil })
    }

    func testWeeklyRuleSchedulesOnTimeOnlyOnMatchingWeekday() {
        let targetWeekday = cal.component(.weekday, from: cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now))!)
        let med = MedicineSnapshot(id: UUID(), name: "Weekly", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0, weekdays: [targetWeekday])])
        let p = plan([med])
        XCTAssertTrue(p.onTime.allSatisfy { cal.component(.weekday, from: $0.scheduledFor) == targetWeekday })
        XCTAssertGreaterThanOrEqual(p.onTime.count, 1)
    }

    func testEveryNDaysSchedulesOnTimeOnAnchoredDays() {
        let med = MedicineSnapshot(id: UUID(), name: "EveryOther", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0, intervalDays: 2,
                                                        anchorDate: cal.startOfDay(for: now))])
        let p = plan([med])
        // Anchored at today, every 2 days → today, +2, +4, +6 within the 7-day horizon.
        XCTAssertGreaterThanOrEqual(p.onTime.count, 3)
        XCTAssertTrue(p.onTime.allSatisfy { !$0.isEscalation && $0.leadMinutes == nil })
    }

    func testDaysOfMonthSchedulesOnTimeWhenDayFallsInHorizon() {
        // now = Jun 16; days-of-month [18] → exactly Jun 18 within the window.
        let med = MedicineSnapshot(id: UUID(), name: "Monthly", dosage: nil,
                                   rules: [DoseSlotRule(hour: 9, minute: 0, daysOfMonth: [18])])
        let p = plan([med])
        XCTAssertEqual(p.onTime.count, 1)
        XCTAssertEqual(cal.component(.day, from: p.onTime.first!.scheduledFor), 18)
    }

    func testDuplicateRulesAreDeduped() {
        let id = UUID()
        let med = MedicineSnapshot(id: id, name: "Dup", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0), DoseSlotRule(hour: 8, minute: 0)])
        let p = plan([med])
        XCTAssertEqual(p.onTime.count, expectedDailyOccurrences(hour: 8).count, "duplicate identical rules collapse")
    }

    // MARK: - Budget order: on-time FIRST, never dropped for escalation/lead-time

    func testTotalNeverExceedsBudget() {
        let p = plan(dailyMeds(50), escalation: true)
        XCTAssertLessThanOrEqual(p.total, NotificationPlanner.maxPending)
    }

    func testOnTimeGetsFirstClaimThenEscalationThenLeadTime() {
        // One ongoing daily med, escalation on, 10-min lead, tight budget = sentinel(1, reserved for
        // the ongoing schedule) + onTime(7) + 2 leftover.
        let med = MedicineSnapshot(id: UUID(), name: "M", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0)], leadTimeMinutes: 10)
        let p = plan([med], escalation: true, budget: 10)
        let onCount = expectedDailyOccurrences(hour: 8).count
        XCTAssertEqual(p.onTime.count, onCount, "every on-time reminder is kept (first claim)")
        XCTAssertEqual(p.escalations.count, 10 - onCount - 1, "escalations take the leftover, soonest-first")
        XCTAssertTrue(p.leadTime.isEmpty, "lead-time is lowest — nothing left for it")
        XCTAssertNotNil(p.sentinelFireDate, "ongoing schedule → coverage-end sentinel reserved")
        XCTAssertEqual(p.total, 10)
    }

    func testOnTimeTruncatedSoonestFirstWhenOverBudget() {
        let p = plan(dailyMeds(1, hour: 8), escalation: true, budget: 3)
        XCTAssertEqual(p.onTime.count, 2, "on-time trimmed to the budget minus the reserved sentinel")
        XCTAssertTrue(p.baseTruncated)
        XCTAssertTrue(p.escalations.isEmpty, "no budget left → on-time is never sacrificed for escalation")
        XCTAssertTrue(p.leadTime.isEmpty)
        // The soonest occurrences survive; the sentinel fires when the first UNcovered dose is due.
        XCTAssertEqual(p.onTime.map { $0.scheduledFor }, Array(expectedDailyOccurrences(hour: 8).prefix(2)))
        XCTAssertEqual(p.sentinelFireDate, expectedDailyOccurrences(hour: 8)[2])
        XCTAssertEqual(p.total, 3)
    }

    func testManyMedsTruncateOnTimeAndFlagIt() {
        let p = plan(dailyMeds(20), escalation: true)   // 20 × ~7 = ~140 on-time > 64
        XCTAssertEqual(p.onTime.count, NotificationPlanner.maxPending - 1, "one slot reserved for the sentinel")
        XCTAssertTrue(p.baseTruncated)
        XCTAssertTrue(p.escalations.isEmpty)
        XCTAssertTrue(p.leadTime.isEmpty)
        XCTAssertNotNil(p.sentinelFireDate)
        XCTAssertEqual(p.total, NotificationPlanner.maxPending)
    }

    func testEscalationDisabledMeansNoEscalations() {
        let p = plan(dailyMeds(2), escalation: false)
        XCTAssertTrue(p.escalations.isEmpty)
    }

    // MARK: - Refill sentinel: coverage must never run out silently

    /// An ongoing medicine always has doses beyond the horizon — the plan carries one sentinel firing
    /// exactly when coverage ends, so a user who never opens the app (and whose background refresh
    /// doesn't run) gets an "open Dose" nudge instead of total reminder silence.
    func testOngoingMedicineArmsSentinelAtHorizonEnd() {
        let p = plan(dailyMeds(1))
        XCTAssertEqual(p.sentinelFireDate, now.addingTimeInterval(NotificationPlanner.defaultWindow),
                       "coverage runs out at the horizon → sentinel fires there")
    }

    /// A course that ends inside the window is FULLY covered — no doses beyond coverage, no sentinel.
    func testBoundedCourseWithinWindowArmsNoSentinel() {
        let med = MedicineSnapshot(id: UUID(), name: "Course", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0)],
                                   createdAt: cal.startOfDay(for: now),
                                   endDate: cal.date(byAdding: .day, value: 3, to: now)!)
        XCTAssertNil(plan([med]).sentinelFireDate)
    }

    func testNoMedicinesNoSentinel() {
        XCTAssertNil(plan([]).sentinelFireDate)
    }

    /// Heavy load: the sentinel survives truncation (reserved slot) and fires no later than the first
    /// dropped occurrence — the moment reminders would have gone silent.
    func testTruncatedPlanSentinelFiresWhenFirstUncoveredDoseIsDue() {
        let p = plan(dailyMeds(20))   // ~140 candidates ≫ 64
        XCTAssertTrue(p.baseTruncated)
        let sentinel = try! XCTUnwrap(p.sentinelFireDate)
        XCTAssertGreaterThanOrEqual(sentinel, p.onTime.last!.fireDate, "fires after the last covered dose")
        XCTAssertLessThan(sentinel, now.addingTimeInterval(NotificationPlanner.defaultWindow),
                          "…but before the horizon: right when the first UNcovered dose is due")
        XCTAssertLessThanOrEqual(p.total, NotificationPlanner.maxPending)
    }

    // MARK: - Snooze survival: the plan re-arms pending snoozes from the log

    /// A slot whose latest log is `.snoozed` (with the 10-min window still open) is re-armed by the
    /// plan with the SAME deterministic id and the REMAINING fire time — this is what makes a snooze
    /// survive reschedule's wipe-and-replace instead of being silently destroyed.
    func testPlanRebuildsSnoozeFromLatestSnoozedLog() {
        let med = MedicineSnapshot(id: UUID(), name: "Med", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0)])
        let slot = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 8))!
        let localNow = slot.addingTimeInterval(5 * 60)                       // 08:05
        let snoozed = DoseLogSnapshot(medicineID: med.id, scheduledFor: slot,
                                      action: .snoozed, actionedAt: slot.addingTimeInterval(120)) // 08:02
        let p = NotificationPlanner.plan(medicines: [med], logs: [snoozed], now: localNow,
                                         escalationEnabled: false, calendar: cal)
        XCTAssertEqual(p.snoozes.map(\.id), [NotificationPlanner.snoozeID(med.id, slot)])
        XCTAssertEqual(p.snoozes.first?.fireDate,
                       snoozed.actionedAt.addingTimeInterval(NotificationPlanner.escalationDelay),
                       "re-armed at the REMAINING time (08:12), not a fresh 10 minutes")
    }

    /// A take/skip after the snooze settles the slot — the latest log is no longer `.snoozed`, so
    /// nothing re-arms (same latest-log rule the engine's status uses).
    func testSnoozedThenTakenSlotDoesNotRebuildSnooze() {
        let med = MedicineSnapshot(id: UUID(), name: "Med", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0)])
        let slot = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 8))!
        let logs = [
            DoseLogSnapshot(medicineID: med.id, scheduledFor: slot, action: .snoozed,
                            actionedAt: slot.addingTimeInterval(120)),
            DoseLogSnapshot(medicineID: med.id, scheduledFor: slot, action: .taken,
                            actionedAt: slot.addingTimeInterval(180)),
        ]
        let p = NotificationPlanner.plan(medicines: [med], logs: logs, now: slot.addingTimeInterval(5 * 60),
                                         escalationEnabled: false, calendar: cal)
        XCTAssertTrue(p.snoozes.isEmpty, "a settled slot never re-arms its snooze")
    }

    /// An elapsed snooze window (fire time already past) has nothing left to deliver.
    func testElapsedSnoozeIsNotRebuilt() {
        let med = MedicineSnapshot(id: UUID(), name: "Med", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0)])
        let slot = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 8))!
        let snoozed = DoseLogSnapshot(medicineID: med.id, scheduledFor: slot,
                                      action: .snoozed, actionedAt: slot.addingTimeInterval(120))
        let p = NotificationPlanner.plan(medicines: [med], logs: [snoozed],
                                         now: slot.addingTimeInterval(20 * 60),   // 08:20 > 08:12 fire
                                         escalationEnabled: false, calendar: cal)
        XCTAssertTrue(p.snoozes.isEmpty)
    }

    /// A snooze for a medicine that is no longer in the plan input (archived/deleted) dies with the
    /// wipe — it must not be resurrected from its orphaned log.
    func testSnoozeForRemovedMedicineIsNotRebuilt() {
        let med = MedicineSnapshot(id: UUID(), name: "Med", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0)])
        let slot = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 8))!
        let snoozed = DoseLogSnapshot(medicineID: UUID(),   // some other (removed) medicine's log
                                      scheduledFor: slot, action: .snoozed,
                                      actionedAt: slot.addingTimeInterval(120))
        let p = NotificationPlanner.plan(medicines: [med], logs: [snoozed], now: slot.addingTimeInterval(5 * 60),
                                         escalationEnabled: false, calendar: cal)
        XCTAssertTrue(p.snoozes.isEmpty)
    }

    func testEscalationFiresTenMinutesAfterOccurrence() {
        let p = plan(dailyMeds(1), escalation: true)
        let esc = try! XCTUnwrap(p.escalations.sorted { $0.fireDate < $1.fireDate }.first)
        XCTAssertEqual(esc.fireDate.timeIntervalSince(esc.scheduledFor), NotificationPlanner.escalationDelay)
        XCTAssertTrue(esc.isEscalation)
    }

    // MARK: - Bounded courses

    func testBoundedCourseCoversEveryDayInHorizonThenStops() {
        let endDate = cal.date(byAdding: .day, value: 5, to: now)!
        let med = MedicineSnapshot(id: UUID(), name: "Course", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0)],
                                   createdAt: cal.startOfDay(for: now), endDate: endDate)
        let p = plan([med])
        let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: endDate)!
        let expected = expectedDailyOccurrences(hour: 8, end: endOfDay)
        XCTAssertGreaterThanOrEqual(expected.count, 5)
        XCTAssertEqual(p.onTime.count, expected.count, "every course day covered, not just the first")
        XCTAssertEqual(Set(p.onTime.map { $0.scheduledFor }), Set(expected))
        XCTAssertTrue(p.onTime.allSatisfy { $0.scheduledFor <= endOfDay }, "nothing after the end day")
    }

    func testNoRemindersAfterEndDate() {
        let endDate = cal.date(byAdding: .day, value: -1, to: now)!
        let med = MedicineSnapshot(id: UUID(), name: "Finished", dosage: nil,
                                   rules: [DoseSlotRule(hour: 8, minute: 0)],
                                   createdAt: cal.date(byAdding: .day, value: -10, to: now)!, endDate: endDate)
        XCTAssertEqual(plan([med], escalation: true).total, 0)
    }

    // MARK: - Lead-time

    func testLeadTimeSchedulesExtraReminderBeforeDose() {
        let med = MedicineSnapshot(id: UUID(), name: "Aspirin", dosage: "100 mg",
                                   rules: [DoseSlotRule(hour: 8, minute: 0)], leadTimeMinutes: 15)
        let p = plan([med])
        XCTAssertEqual(p.onTime.count, expectedDailyOccurrences(hour: 8).count, "on-time unchanged by lead-time")
        let lead = try! XCTUnwrap(p.leadTime.sorted { $0.fireDate < $1.fireDate }.first)
        XCTAssertEqual(lead.leadMinutes, 15)
        XCTAssertEqual(lead.scheduledFor.timeIntervalSince(lead.fireDate), 15 * 60, accuracy: 1)
        XCTAssertEqual(cal.component(.hour, from: lead.fireDate), 7)
        XCTAssertEqual(cal.component(.minute, from: lead.fireDate), 45)
    }

    func testLeadTimeYieldsToOnTimeUnderBudget() {
        let meds = dailyMeds(5).map {
            MedicineSnapshot(id: $0.id, name: $0.name, dosage: $0.dosage, rules: $0.rules, leadTimeMinutes: 15)
        }
        // 5 × 7 = 35 on-time. Budget 35 → sentinel reserved (ongoing schedules) + 34 on-time fill it;
        // lead-time gets nothing.
        let p = plan(meds, budget: 35)
        XCTAssertEqual(p.onTime.count, 34)
        XCTAssertNotNil(p.sentinelFireDate)
        XCTAssertTrue(p.leadTime.isEmpty, "no budget left → lead-time dropped, never on-time")
        XCTAssertEqual(p.total, 35)
    }

    func testNoLeadTimeProducesNoLeadReminders() {
        let p = plan(dailyMeds(1))
        XCTAssertTrue(p.leadTime.isEmpty)
    }

    // MARK: - Resolved (taken/skipped) doses are NOT scheduled — the double-dose fix

    private func takenLog(_ medID: UUID, _ occ: Date) -> DoseLogSnapshot {
        DoseLogSnapshot(medicineID: medID, scheduledFor: occ, action: .taken, actionedAt: occ)
    }

    func testTakenSlotIsNotScheduledButOtherDaysAre() {
        let medID = UUID()
        let med = MedicineSnapshot(id: medID, name: "M", dosage: nil, rules: [DoseSlotRule(hour: 8, minute: 0)],
                                   leadTimeMinutes: 15)
        let occs = expectedDailyOccurrences(hour: 8)
        let takenOcc = occs.first!   // today's 08:00
        let p = plan([med], logs: [takenLog(medID, takenOcc)], escalation: true)

        // The taken occurrence is absent from on-time, escalation, AND lead-time…
        XCTAssertFalse(p.onTime.contains { ExecutionEngine.sameSlot($0.scheduledFor, takenOcc) },
                       "a taken dose is never (re)scheduled — this is what stops the double-dose prompt")
        XCTAssertFalse(p.escalations.contains { ExecutionEngine.sameSlot($0.scheduledFor, takenOcc) })
        XCTAssertFalse(p.leadTime.contains { ExecutionEngine.sameSlot($0.scheduledFor, takenOcc) })
        // …but every OTHER day still has its on-time reminder.
        XCTAssertEqual(p.onTime.count, occs.count - 1)
        XCTAssertEqual(Set(p.onTime.map { $0.scheduledFor }), Set(occs.dropFirst()))
    }

    func testSkippedSlotIsNotScheduled() {
        let medID = UUID()
        let med = MedicineSnapshot(id: medID, name: "M", dosage: nil, rules: [DoseSlotRule(hour: 8, minute: 0)])
        let takenOcc = expectedDailyOccurrences(hour: 8).first!
        let skip = DoseLogSnapshot(medicineID: medID, scheduledFor: takenOcc, action: .skipped, actionedAt: takenOcc)
        let p = plan([med], logs: [skip])
        XCTAssertFalse(p.onTime.contains { ExecutionEngine.sameSlot($0.scheduledFor, takenOcc) })
    }

    func testResolvedSlotOfOneMedDoesNotAffectAnother() {
        let a = UUID(), b = UUID()
        let medA = MedicineSnapshot(id: a, name: "A", dosage: nil, rules: [DoseSlotRule(hour: 8, minute: 0)])
        let medB = MedicineSnapshot(id: b, name: "B", dosage: nil, rules: [DoseSlotRule(hour: 8, minute: 0)])
        let occ = expectedDailyOccurrences(hour: 8).first!
        let p = plan([medA, medB], logs: [takenLog(a, occ)])
        XCTAssertFalse(p.onTime.contains { $0.medicineID == a && ExecutionEngine.sameSlot($0.scheduledFor, occ) })
        XCTAssertTrue(p.onTime.contains { $0.medicineID == b && ExecutionEngine.sameSlot($0.scheduledFor, occ) },
                      "another med's same-time dose is unaffected")
    }

    // MARK: - Per-occurrence identifiers (so cancelling one slot can't touch others)

    func testSlotIDsAreDeterministicAndPerOccurrence() {
        let med = UUID()
        let slot1 = now.addingTimeInterval(3600)
        let slot2 = now.addingTimeInterval(2 * 3600)
        XCTAssertEqual(NotificationPlanner.slotIDs(med, slot1),
                       [NotificationPlanner.onTimeID(med, slot1),
                        NotificationPlanner.escID(med, slot1),
                        NotificationPlanner.leadID(med, slot1),
                        NotificationPlanner.snoozeID(med, slot1)],
                       "slotIDs covers all four reminder kinds, incl. the snooze")
        XCTAssertTrue(NotificationPlanner.onTimeID(med, slot1).hasPrefix("ontime."))
        XCTAssertTrue(NotificationPlanner.snoozeID(med, slot1).hasPrefix("snooze."))
        // Distinct occurrences → disjoint id sets (cancelling slot1 can't remove slot2's reminders).
        XCTAssertTrue(Set(NotificationPlanner.slotIDs(med, slot1))
            .isDisjoint(with: Set(NotificationPlanner.slotIDs(med, slot2))))
    }
}
