import XCTest
import SwiftData
@testable import Dose

/// Unarchive + permanent delete for archived medicines. Proves an unarchived med becomes visible again
/// (passes the shared `activeConfirmed` filter) AND is re-scheduled (its reminders are re-planned, not
/// just the flag flipped), and that permanent delete removes the med + its rules while keeping history.
@MainActor
final class ArchiveTests: XCTestCase {
    private func makeStore() throws -> ModelContext {
        let schema = DoseStore.currentSchema
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    @discardableResult
    private func med(_ ctx: ModelContext, _ name: String, trustState: TrustState = .confirmed, isActive: Bool) -> Medicine {
        let m = Medicine(name: name, dosage: "5 mg", trustState: trustState, isActive: isActive)
        let dt = DoseTime(hour: 8, minute: 0)   // daily → produces on-time reminders when active
        m.doseTimes = [dt]
        ctx.insert(m); ctx.insert(dt)
        return m
    }

    func testArchivedFilterReturnsOnlyInactiveConfirmed() throws {
        let ctx = try makeStore()
        let active = med(ctx, "Active", isActive: true)
        let archived = med(ctx, "Archived", isActive: false)
        let draft = med(ctx, "Draft", trustState: .draft, isActive: false)
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<Medicine>())

        XCTAssertEqual(Set(Medicine.archived(all).map(\.id)), [archived.id],
                       "archived list = inactive + confirmed only; excludes active and non-confirmed")
        XCTAssertFalse(Medicine.archived(all).contains { $0.id == active.id })
        XCTAssertFalse(Medicine.archived(all).contains { $0.id == draft.id })
    }

    func testUnarchiveRestoresVisibilityAcrossSurfaces() throws {
        let ctx = try makeStore()
        let m = med(ctx, "Vitamin D", isActive: false)
        try ctx.save()
        XCTAssertTrue(Medicine.activeConfirmed([m]).isEmpty, "archived med is excluded from the active surfaces")

        MedicineWriter.setArchived(m, false, context: ctx, escalationEnabled: false)

        XCTAssertTrue(m.isActive, "unarchive flips it active")
        XCTAssertEqual(Medicine.activeConfirmed([m]).map(\.id), [m.id],
                       "it now passes the shared filter → reappears on Today/History/Week/report")
    }

    func testUnarchiveReArmsNotifications() throws {
        let ctx = try makeStore()
        let m = med(ctx, "Vitamin D", isActive: false)
        try ctx.save()

        // While archived, the shared filter excludes it, so nothing is planned for it.
        let beforeMeds = Medicine.activeConfirmed([m]).map { $0.snapshot() }
        XCTAssertTrue(NotificationPlanner.plan(medicines: beforeMeds, logs: [], now: .now, escalationEnabled: false).onTime.isEmpty)

        MedicineWriter.setArchived(m, false, context: ctx, escalationEnabled: false)

        // After unarchive, the restored med is scheduled again (on-time reminders are planned).
        let afterMeds = Medicine.activeConfirmed([m]).map { $0.snapshot() }
        let plan = NotificationPlanner.plan(medicines: afterMeds, logs: [], now: .now, escalationEnabled: false)
        XCTAssertFalse(plan.onTime.isEmpty, "unarchive re-plans the med's reminders — not just a flag flip")
        XCTAssertTrue(plan.onTime.allSatisfy { $0.medicineID == m.id })
    }

    func testPermanentDeleteRemovesMedicineAndRulesButKeepsHistory() throws {
        let ctx = try makeStore()
        let m = med(ctx, "Cv", isActive: false)
        let medID = m.id
        // A past dose log for this med — must SURVIVE deletion (no Medicine relationship → no cascade).
        ctx.insert(DoseLog(medicineID: medID, medicineName: "Cv", dosage: "5 mg",
                           scheduledFor: .now, action: .taken))
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<DoseTime>()).count, 1)

        MedicineWriter.deletePermanently(m, context: ctx, escalationEnabled: false)

        XCTAssertTrue(try ctx.fetch(FetchDescriptor<Medicine>()).isEmpty, "the medicine is gone")
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<DoseTime>()).isEmpty, "its DoseTime rules cascade-deleted")
        let logs = try ctx.fetch(FetchDescriptor<DoseLog>())
        XCTAssertEqual(logs.count, 1, "DoseLog history is kept")
        XCTAssertEqual(logs.first?.medicineID, medID)
    }
}
