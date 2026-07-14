import XCTest
import SwiftData
@testable import Dose

/// The double-dose fix at the action layer: taking or skipping a dose cancels EVERY pending reminder
/// for that exact occurrence — on-time, escalation, lead-time, AND a pending snooze — so no further
/// "Time for X" can fire for an already-recorded dose. Uses the `addPending`/`removePending` test seams
/// to capture scheduled/cancelled requests without the live notification center. (The Today-card path
/// calls the same `NotificationScheduler.cancelSlot`.)
@MainActor
final class NotificationCancellationTests: XCTestCase {
    private func makeHandler() throws -> NotificationActionHandler {
        let schema = DoseStore.currentSchema
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return NotificationActionHandler(container: container)
    }

    private func captureCancellations(_ body: () -> Void) -> [String] {
        var captured: [String] = []
        let prev = NotificationScheduler.shared.removePending
        NotificationScheduler.shared.removePending = { captured.append(contentsOf: $0) }
        defer { NotificationScheduler.shared.removePending = prev }
        body()
        return captured
    }

    private func captureScheduled(_ body: () -> Void) -> [String] {
        var ids: [String] = []
        let prev = NotificationScheduler.shared.addPending
        NotificationScheduler.shared.addPending = { ids.append($0.identifier) }
        defer { NotificationScheduler.shared.addPending = prev }
        body()
        return ids
    }

    func testTakeCancelsAllFourReminderKindsForThatSlot() throws {
        let handler = try makeHandler()
        let med = UUID()
        let slot = Date(timeIntervalSince1970: 1_780_000_000)

        let captured = captureCancellations {
            handler.handleAction(NotificationScheduler.takeAction, medicineID: med, name: "Aspirin",
                                 dosage: "100 mg", scheduledFor: slot)
        }
        XCTAssertEqual(Set(captured), Set(NotificationPlanner.slotIDs(med, slot)),
                       "a take cancels exactly the slot's on-time + escalation + lead-time + snooze")
        XCTAssertTrue(captured.contains(NotificationPlanner.snoozeID(med, slot)), "incl. the snooze")
    }

    func testSkipCancelsAllFourReminderKindsForThatSlot() throws {
        let handler = try makeHandler()
        let med = UUID()
        let slot = Date(timeIntervalSince1970: 1_780_003_600)

        let captured = captureCancellations {
            handler.handleAction(NotificationScheduler.skipAction, medicineID: med, name: "Aspirin",
                                 dosage: nil, scheduledFor: slot)
        }
        XCTAssertEqual(Set(captured), Set(NotificationPlanner.slotIDs(med, slot)))
        XCTAssertTrue(captured.contains(NotificationPlanner.snoozeID(med, slot)))
    }

    /// The reported gap, end to end: a snooze armed for an occurrence is cancelled when that dose is
    /// taken from a notification — so the snooze can't fire "Time for X" for an already-taken dose.
    func testSnoozeArmedThenTakeCancelsItFromNotificationPath() throws {
        let handler = try makeHandler()
        let med = UUID()
        let slot = Date(timeIntervalSince1970: 1_780_000_000)

        // Arm the snooze (as "Remind in 10 min" does) and capture the id it actually schedules.
        let armed = captureScheduled {
            NotificationScheduler.shared.scheduleSnooze(medicineID: med, medicineName: "Aspirin",
                                                        dosage: "100 mg", scheduledFor: slot)
        }
        XCTAssertEqual(armed, [NotificationPlanner.snoozeID(med, slot)],
                       "snooze armed with the deterministic per-occurrence id (not a random uuid)")

        // Take the dose for that occurrence → the armed snooze id is among the cancelled requests.
        let removed = captureCancellations {
            handler.handleAction(NotificationScheduler.takeAction, medicineID: med, name: "Aspirin",
                                 dosage: "100 mg", scheduledFor: slot)
        }
        XCTAssertTrue(removed.contains(armed[0]),
                      "taking the dose cancels the pending snooze for that slot — no double-dose prompt")
    }

    // MARK: - Lead-time heads-ups are informational: a glance-tap must never write a dose record

    private func makeHandlerAndContainer() throws -> (NotificationActionHandler, ModelContainer) {
        let schema = DoseStore.currentSchema
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return (NotificationActionHandler(container: container), container)
    }

    /// THE bug: a "coming up in N min" heads-up carries the FUTURE dose's slot, and the default tap
    /// (just opening the app from the banner) recorded it `.taken` half an hour early AND cancelled the
    /// real on-time reminder. A default tap on `kind == "leadtime"` must be a pure navigation: no log,
    /// no cancellation.
    func testDefaultTapOnLeadTimeHeadsUpRecordsNothing() throws {
        let (handler, container) = try makeHandlerAndContainer()
        let med = UUID()
        let slot = Date(timeIntervalSince1970: 1_780_000_000)

        var written: DoseLog?
        let cancelled = captureCancellations {
            written = handler.handleAction(UNNotificationDefaultActionIdentifier, kind: "leadtime",
                                           medicineID: med, name: "Aspirin", dosage: "100 mg",
                                           scheduledFor: slot)
        }
        XCTAssertNil(written, "tapping a heads-up to open the app is not a dose action")
        XCTAssertTrue(cancelled.isEmpty, "the slot's real on-time reminder must survive the tap")
        let logs = try container.mainContext.fetch(FetchDescriptor<DoseLog>())
        XCTAssertTrue(logs.isEmpty, "no DoseLog of any kind is written for a heads-up glance")
    }

    /// Regression guard: the default tap on a REAL dose reminder (primary/escalation/snooze — and
    /// legacy payloads with no kind) still records the take, exactly as designed.
    func testDefaultTapOnDoseRemindersStillTakes() throws {
        for kind in ["primary", "escalation", "snooze", nil] as [String?] {
            let (handler, _) = try makeHandlerAndContainer()
            let med = UUID()
            let slot = Date(timeIntervalSince1970: 1_780_000_000)
            let log = handler.handleAction(UNNotificationDefaultActionIdentifier, kind: kind,
                                           medicineID: med, name: "Aspirin", dosage: nil,
                                           scheduledFor: slot)
            XCTAssertEqual(log?.action, .taken, "default tap takes for kind \(kind ?? "nil")")
        }
    }

    /// The explicit Take button on a heads-up IS a deliberate dose action (taking a few minutes early
    /// is the user's call) — it must keep recording and cancelling the slot.
    func testExplicitTakeOnLeadTimeStillRecords() throws {
        let (handler, _) = try makeHandlerAndContainer()
        let med = UUID()
        let slot = Date(timeIntervalSince1970: 1_780_000_000)
        let cancelled = captureCancellations {
            let log = handler.handleAction(NotificationScheduler.takeAction, kind: "leadtime",
                                           medicineID: med, name: "Aspirin", dosage: nil,
                                           scheduledFor: slot)
            XCTAssertEqual(log?.action, .taken)
        }
        XCTAssertEqual(Set(cancelled), Set(NotificationPlanner.slotIDs(med, slot)))
    }

    /// N1: a heads-up no longer offers "Remind in 10 min" (its category omits snooze), because that
    /// nudge had no `.snoozed` log and was silently destroyed by the next reschedule. A snooze that
    /// somehow still arrives for a lead-time kind is now a pure no-op — it must NOT arm a nudge that
    /// would vanish, NOT cancel the slot, and NOT write a log.
    /// FAIL-BEFORE: the handler armed a nudge (scheduled the snooze id). PASS-AFTER: nothing happens.
    func testSnoozeOnLeadTimeIsNoOp() throws {
        let (handler, container) = try makeHandlerAndContainer()
        let med = UUID()
        let slot = Date(timeIntervalSince1970: 1_780_000_000)

        var written: DoseLog?
        var cancelled: [String] = []
        let scheduled = captureScheduled {
            cancelled = captureCancellations {
                written = handler.handleAction(NotificationScheduler.snoozeAction, kind: "leadtime",
                                               medicineID: med, name: "Aspirin", dosage: nil,
                                               scheduledFor: slot)
            }
        }
        XCTAssertTrue(scheduled.isEmpty, "no un-durable nudge is armed for a heads-up snooze")
        XCTAssertTrue(cancelled.isEmpty, "the real on-time reminder survives")
        XCTAssertNil(written)
        let logs = try container.mainContext.fetch(FetchDescriptor<DoseLog>())
        XCTAssertTrue(logs.isEmpty, "no .snoozed log for a not-yet-due dose")
    }

    /// The lead-time category exposes only Take + Skip; the dose category keeps the snooze action.
    func testLeadTimeCategoryOmitsSnoozeButDoseCategoryKeepsIt() {
        let cats = NotificationScheduler.categories()
        let leadTime = cats.first { $0.identifier == NotificationScheduler.leadTimeCategoryID }
        let dose = cats.first { $0.identifier == NotificationScheduler.categoryID }
        XCTAssertNotNil(leadTime); XCTAssertNotNil(dose)
        XCTAssertFalse(leadTime?.actions.contains { $0.identifier == NotificationScheduler.snoozeAction } ?? true,
                       "a heads-up must not show 'Remind in 10 min'")
        XCTAssertTrue(dose?.actions.contains { $0.identifier == NotificationScheduler.snoozeAction } ?? false,
                      "a real dose reminder still offers snooze")
    }

    /// A lead-time content is stamped with the lead-time category (so the OS shows the snooze-free
    /// buttons); a normal dose reminder keeps the dose category.
    /// FAIL-BEFORE: lead-time content used the dose category. PASS-AFTER: it uses the lead-time one.
    func testLeadTimeContentUsesLeadTimeCategory() {
        let lead = NotificationScheduler.makeContent(name: "Aspirin", dosage: nil, leadMinutes: 30, userInfo: [:])
        XCTAssertEqual(lead.categoryIdentifier, NotificationScheduler.leadTimeCategoryID)
        let onTime = NotificationScheduler.makeContent(name: "Aspirin", dosage: nil, userInfo: [:])
        XCTAssertEqual(onTime.categoryIdentifier, NotificationScheduler.categoryID)
    }

    // MARK: - A pending snooze must survive reschedule's wipe-and-replace

    /// THE bug: `reschedule` wipes ALL pending requests, and a "Remind in 10 min" one-shot existed
    /// ONLY in the notification center — the planner rebuilt on-time/escalation/lead-time but never
    /// snoozes. So opening the app (or a background refresh, or editing any medicine) silently
    /// destroyed the promised reminder while Today kept showing "snoozed until…". The plan must
    /// re-arm the snooze from the slot's latest `.snoozed` log.
    func testRescheduleRebuildsPendingSnoozeFromLog() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let slot = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 8))!
        let snoozedAt = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 8, minute: 2))!
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 8, minute: 5))!

        let schema = DoseStore.currentSchema
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let ctx = ModelContext(container)
        let med = Medicine(name: "Aspirin", trustState: .confirmed)
        let dt = DoseTime(hour: 8, minute: 0)
        med.doseTimes = [dt]
        ctx.insert(med); ctx.insert(dt)
        let log = DoseLog(medicineID: med.id, medicineName: "Aspirin", scheduledFor: slot,
                          action: .snoozed, actionedAt: snoozedAt)
        ctx.insert(log)

        let scheduled = captureScheduled {
            NotificationScheduler.shared.reschedule(medicines: [med], logs: [log],
                                                    escalationEnabled: false, now: now)
        }
        XCTAssertTrue(scheduled.contains(NotificationPlanner.snoozeID(med.id, slot)),
                      "a reschedule re-arms the pending snooze instead of silently destroying it")
    }

    // MARK: - Refill sentinel: reminders must never run out silently

    /// THE gap: one-shots cover ~7 days (less when the 64-cap truncates), refilled only by app-opens
    /// or discretionary background refresh. If neither happens, reminders just STOP — total silence on
    /// a medication app, and the in-app truncation banner is invisible to someone not opening the app.
    /// Whenever doses exist beyond the plan's coverage, the reschedule must arm one "open Dose to
    /// refresh" sentinel at the moment coverage runs out.
    func testRescheduleArmsRefillSentinelForOngoingMedicine() throws {
        let schema = DoseStore.currentSchema
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let ctx = ModelContext(container)
        let med = Medicine(name: "Aspirin", trustState: .confirmed)   // ongoing daily med
        let dt = DoseTime(hour: 8, minute: 0)
        med.doseTimes = [dt]
        ctx.insert(med); ctx.insert(dt)

        let scheduled = captureScheduled {
            NotificationScheduler.shared.reschedule(medicines: [med], logs: [], escalationEnabled: false)
        }
        XCTAssertTrue(scheduled.contains("refill.sentinel"),
                      "an ongoing schedule arms a coverage-end sentinel so reminders can't run out silently")
    }

    // MARK: - C2: a failed save must not cancel the reminder or read as success

    /// If persisting the `DoseLog` fails, a take from a notification must NOT cancel the slot's pending
    /// reminders (so the dose is re-prompted) and must return no log (no false success).
    /// FAIL-BEFORE: `record` swallowed the error and returned a log, so the handler cancelled the slot
    /// for a dose that never persisted. PASS-AFTER: no log, no cancellation.
    func testFailedSaveDoesNotCancelReminderOrReportSuccess() throws {
        let handler = try makeHandler()
        let med = UUID()
        let slot = Date(timeIntervalSince1970: 1_780_000_000)
        DoseActionWriter.forceSaveFailureForTesting = true
        defer { DoseActionWriter.forceSaveFailureForTesting = false }

        var written: DoseLog?
        let cancelled = captureCancellations {
            written = handler.handleAction(NotificationScheduler.takeAction, medicineID: med, name: "Aspirin",
                                           dosage: "100 mg", scheduledFor: slot)
        }
        XCTAssertNil(written, "a failed save returns no log — not a false success")
        XCTAssertTrue(cancelled.isEmpty, "the slot's reminders must survive so the dose is re-prompted")
    }

    /// The Today take/skip path calls exactly `cancelSlot(medicineID:scheduledFor:)`; confirm it also
    /// removes the slot's snooze (the same mechanism the notification path uses).
    func testTodayPathCancelSlotRemovesTheSnooze() {
        let med = UUID()
        let slot = Date(timeIntervalSince1970: 1_780_000_000)
        let removed = captureCancellations {
            NotificationScheduler.shared.cancelSlot(medicineID: med, scheduledFor: slot)
        }
        XCTAssertTrue(removed.contains(NotificationPlanner.snoozeID(med, slot)),
                      "the Today card's take/skip (cancelSlot) cancels the slot's snooze too")
    }
}
