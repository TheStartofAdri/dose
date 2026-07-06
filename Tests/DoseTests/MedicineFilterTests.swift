import XCTest
import SwiftData
@testable import Dose

/// The core "they can't disagree" guarantee: every medicine-list surface (Today, History, Export
/// report, This week) draws from the SAME confirmed+active set via `Medicine.activeConfirmed`. The bug
/// was Export report showing archived meds ("Aria"/"Cv") that Today excludes; these lock that shut.
@MainActor
final class MedicineFilterTests: XCTestCase {
    private func makeStore() throws -> ModelContext {
        let schema = DoseStore.currentSchema
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    @discardableResult
    private func med(_ ctx: ModelContext, _ name: String, trustState: TrustState, isActive: Bool) -> Medicine {
        let m = Medicine(name: name, trustState: trustState, isActive: isActive)
        let dt = DoseTime(hour: 8, minute: 0)   // daily → a dose every day
        m.doseTimes = [dt]
        ctx.insert(m); ctx.insert(dt)
        return m
    }

    func testExportReportShowsTheSameMedicineSetAsTodayAndWeek() throws {
        let ctx = try makeStore()
        let vitD = med(ctx, "Vitamin D", trustState: .confirmed, isActive: true)   // the only real one
        let aria = med(ctx, "Aria", trustState: .draft, isActive: true)            // unconfirmed draft
        let cv   = med(ctx, "Cv",   trustState: .confirmed, isActive: false)       // archived
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<Medicine>())
        XCTAssertEqual(all.count, 3)

        // The single shared base filter (what the Export report's `listed` now uses).
        let reportListed = Medicine.activeConfirmed(all)
        XCTAssertEqual(Set(reportListed.map(\.id)), [vitD.id], "Export report excludes the draft and the archived med")
        XCTAssertFalse(reportListed.contains { $0.name == "Aria" || $0.name == "Cv" })

        // Today and This week, via the engine conveniences (also `Medicine.activeConfirmed`).
        let todayMeds = Set(ExecutionEngine.todaysDoses(confirmedMedicines: all, logs: [], now: .now).map(\.medicineID))
        let weekMeds = Set(ExecutionEngine.scheduledSlots(confirmedMedicines: all, on: .now).map(\.medicineID))

        // The core guarantee: Export report's medicine set == Today's == This week's (all daily here).
        XCTAssertEqual(Set(reportListed.map(\.id)), todayMeds, "Export report == Today medicine set")
        XCTAssertEqual(todayMeds, weekMeds, "Today == This week medicine set")
        XCTAssertEqual(todayMeds, [vitD.id])

        // Explicitly: the draft and archived meds appear on NONE of the surfaces.
        for ghost in [aria.id, cv.id] {
            XCTAssertFalse(reportListed.contains { $0.id == ghost })
            XCTAssertFalse(todayMeds.contains(ghost))
            XCTAssertFalse(weekMeds.contains(ghost))
        }
    }

    func testUnconfirmedDraftNeverAppears() throws {
        let ctx = try makeStore()
        med(ctx, "Real", trustState: .confirmed, isActive: true)
        let draft = med(ctx, "Aria", trustState: .draft, isActive: true)
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<Medicine>())
        XCTAssertFalse(Medicine.activeConfirmed(all).contains { $0.id == draft.id })
        XCTAssertFalse(ExecutionEngine.todaysDoses(confirmedMedicines: all, logs: [], now: .now).contains { $0.medicineID == draft.id })
        XCTAssertFalse(ExecutionEngine.scheduledSlots(confirmedMedicines: all, on: .now).contains { $0.medicineID == draft.id })
    }

    func testArchivedMedicineExcludedConsistently() throws {
        let ctx = try makeStore()
        med(ctx, "Real", trustState: .confirmed, isActive: true)
        let archived = med(ctx, "Cv", trustState: .confirmed, isActive: false)
        try ctx.save()
        let all = try ctx.fetch(FetchDescriptor<Medicine>())
        // v1 policy: archived is excluded everywhere (no "include archived" path).
        XCTAssertFalse(Medicine.activeConfirmed(all).contains { $0.id == archived.id })
        XCTAssertFalse(ExecutionEngine.todaysDoses(confirmedMedicines: all, logs: [], now: .now).contains { $0.medicineID == archived.id })
        XCTAssertFalse(ExecutionEngine.scheduledSlots(confirmedMedicines: all, on: .now).contains { $0.medicineID == archived.id })
    }
}
