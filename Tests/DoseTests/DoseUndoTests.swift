import XCTest
import SwiftData
@testable import Dose

/// m3: undoing a Take/Skip must restore the slot's one-shot reminder (which the take/skip cancelled) —
/// but ONLY for a still-future occurrence; a past slot is not rescheduled. Uses the `addPending` seam to
/// capture what `reschedule` submits. Fail-before: undo deleted the log without rescheduling, so nothing
/// was restored.
@MainActor
final class DoseUndoTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = DoseStore.currentSchema
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func captureScheduled(_ body: () -> Void) -> [String] {
        var ids: [String] = []
        let prev = NotificationScheduler.shared.addPending
        NotificationScheduler.shared.addPending = { ids.append($0.identifier) }
        defer { NotificationScheduler.shared.addPending = prev }
        body()
        return ids
    }

    /// A single-occurrence confirmed medicine (endDate today, one rule at `hour`) + a `.taken` log for
    /// that slot. Single-occurrence so the slot's reminder is isolated. Returns (medicineID, slotDate).
    private func seedTakenSingleOccurrence(_ context: ModelContext, hour: Int, now: Date) -> (UUID, Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let slot = cal.date(bySettingHour: hour, minute: 0, second: 0, of: today)!
        let med = Medicine(name: "X", trustState: .confirmed, isActive: true, endDate: today)
        med.doseTimes = [DoseTime(hour: hour, minute: 0)]
        context.insert(med)
        context.insert(DoseLog(medicineID: med.id, medicineName: "X", scheduledFor: slot, action: .taken))
        try? context.save()
        return (med.id, slot)
    }

    func testUndoReschedulesAFutureSlot() throws {
        let context = try makeContext()
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let (medID, slot) = seedTakenSingleOccurrence(context, hour: 20, now: now)   // 20:00 > 12:00 → future

        let scheduled = captureScheduled {
            DoseUndo.undo(medicineID: medID, scheduledFor: slot, context: context, escalationEnabled: false, now: now)
        }
        XCTAssertTrue(scheduled.contains(NotificationPlanner.onTimeID(medID, slot)),
                      "undo restores the future slot's on-time reminder")
    }

    func testUndoDoesNotRescheduleAPastSlot() throws {
        let context = try makeContext()
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let (medID, slot) = seedTakenSingleOccurrence(context, hour: 6, now: now)    // 06:00 < 12:00 → past

        let scheduled = captureScheduled {
            DoseUndo.undo(medicineID: medID, scheduledFor: slot, context: context, escalationEnabled: false, now: now)
        }
        XCTAssertFalse(scheduled.contains(NotificationPlanner.onTimeID(medID, slot)),
                       "a past slot is not rescheduled")
        XCTAssertTrue(scheduled.filter { $0.hasPrefix("ontime.\(medID.uuidString).") }.isEmpty,
                      "no on-time reminder for an ended, past-only medicine")
    }

    func testUndoWithNoMatchingLogIsNoOp() throws {
        let context = try makeContext()
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let slot = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: now)!
        let scheduled = captureScheduled {
            let removed = DoseUndo.undo(medicineID: UUID(), scheduledFor: slot, context: context,
                                        escalationEnabled: false, now: now)
            XCTAssertEqual(removed, 0, "nothing to undo")
        }
        XCTAssertTrue(scheduled.isEmpty, "no reschedule when there was nothing to undo")
    }
}
