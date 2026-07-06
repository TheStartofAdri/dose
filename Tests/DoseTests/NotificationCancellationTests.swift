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

    /// "Remind in 10 min" on a heads-up arms an extra nudge but must NOT cancel the slot (the real
    /// on-time reminder hasn't fired yet) and must NOT write a `.snoozed` log (the dose isn't due, and
    /// a snooze log would distort the Today status of an upcoming dose).
    func testSnoozeOnLeadTimeAddsNudgeWithoutCancellingSlotOrLogging() throws {
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
        XCTAssertEqual(scheduled, [NotificationPlanner.snoozeID(med, slot)], "the extra nudge is armed")
        XCTAssertTrue(cancelled.isEmpty, "the real on-time reminder survives")
        XCTAssertNil(written)
        let logs = try container.mainContext.fetch(FetchDescriptor<DoseLog>())
        XCTAssertTrue(logs.isEmpty, "no .snoozed log for a not-yet-due dose")
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
