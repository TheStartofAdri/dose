import XCTest
import SwiftData
@testable import Dose

/// Exercises the UPGRADE path that CI missed (the sim was erased between runs, so only fresh
/// installs were tested). Writes a store under the OLD schema, then opens it with the CURRENT
/// schema + migration plan — reproducing the shipped-user upgrade that crashed with Code=134110.
final class MigrationTests: XCTestCase {
    func testUpgradeFromLegacyStorePreservesDataAndDefaultsNewAttributes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dose-migrate-\(UUID().uuidString).store")
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + s) } }

        let medID = UUID()

        // 1) Create a store under the OLD (pre-upgrade) schema — DoseTime without the new attributes,
        //    written with a plain (un-versioned) schema like a shipped user's store.
        do {
            let v1Schema = Schema([DoseSchemaV1.Medicine.self, DoseSchemaV1.DoseTime.self, DoseSchemaV1.DoseLog.self])
            let v1 = try ModelContainer(for: v1Schema, configurations: [ModelConfiguration(schema: v1Schema, url: url)])
            let ctx = ModelContext(v1)
            let med = DoseSchemaV1.Medicine(id: medID, name: "Amoxicillin", dosage: "500 mg", form: "capsule",
                                            trustStateRaw: "confirmed", isActive: true, createdAt: .now)
            let dt = DoseSchemaV1.DoseTime(hour: 9, minute: 0, weekdays: [2, 4, 6])
            med.doseTimes = [dt]
            ctx.insert(med)
            try ctx.save()
        } // v1 container released here so the store file is closed before reopening.

        // 2) Open the SAME store file with the CURRENT schema + migration plan (the app's real path).
        //    Before the fix this threw Code=134110 ("missing mandatory attribute value", daysOfMonth).
        let v2 = try ModelContainer(for: DoseStore.currentSchema, migrationPlan: DoseMigrationPlan.self,
                                    configurations: [ModelConfiguration(schema: DoseStore.currentSchema, url: url)])
        let ctx = ModelContext(v2)

        let meds = try ctx.fetch(FetchDescriptor<Medicine>())
        XCTAssertEqual(meds.count, 1, "the medicine survived the upgrade — no data loss")
        let med = try XCTUnwrap(meds.first)
        XCTAssertEqual(med.id, medID)
        XCTAssertEqual(med.name, "Amoxicillin")
        XCTAssertEqual(med.trustState, .confirmed)

        let dt = try XCTUnwrap(med.doseTimes.first)
        XCTAssertEqual(dt.hour, 9)
        XCTAssertEqual(dt.weekdays, [2, 4, 6], "existing attributes preserved")

        // The new attributes get safe defaults on the migrated old row — this is the 134110 fix.
        XCTAssertEqual(dt.daysOfMonth, [])
        XCTAssertEqual(dt.intervalDays, 0)
        XCTAssertNil(dt.anchorDate)
    }

    /// The path a real on-device store actually takes now: it's at V2 → must upgrade to current (V3).
    /// Writes a genuine V2 store, opens it with the current schema + plan, and asserts data is
    /// preserved, the new Medicine attributes default to nil, and the new `Note` entity is usable.
    func testUpgradeFromV2StorePreservesDataAndDefaultsNewAttributes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dose-migrate-v2-\(UUID().uuidString).store")
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + s) } }

        let medID = UUID()

        // 1) Write a store under the V2 (previously-shipped) schema.
        do {
            let v2Schema = Schema([DoseSchemaV2.Medicine.self, DoseSchemaV2.DoseTime.self, DoseSchemaV2.DoseLog.self])
            let v2 = try ModelContainer(for: v2Schema, configurations: [ModelConfiguration(schema: v2Schema, url: url)])
            let ctx = ModelContext(v2)
            let med = DoseSchemaV2.Medicine(id: medID, name: "Amoxicillin", dosage: "500 mg", form: "capsule",
                                            trustStateRaw: "confirmed", isActive: true, createdAt: .now)
            med.doseTimes = [DoseSchemaV2.DoseTime(hour: 9, minute: 0, weekdays: [2, 4, 6])]
            ctx.insert(med)
            try ctx.save()
        }

        // 2) Open the SAME file with the CURRENT schema (V3) + the migration plan (V2 → V3).
        let current = try ModelContainer(for: DoseStore.currentSchema, migrationPlan: DoseMigrationPlan.self,
                                         configurations: [ModelConfiguration(schema: DoseStore.currentSchema, url: url)])
        let ctx = ModelContext(current)

        let meds = try ctx.fetch(FetchDescriptor<Medicine>())
        XCTAssertEqual(meds.count, 1, "the medicine survived the V2 → V3 upgrade")
        let med = try XCTUnwrap(meds.first)
        XCTAssertEqual(med.id, medID)
        XCTAssertEqual(med.name, "Amoxicillin")
        XCTAssertEqual(med.doseTimes.first?.weekdays, [2, 4, 6], "existing attributes preserved")

        // New v3 attributes default to nil on the migrated row — the migration-safety contract.
        XCTAssertNil(med.iconName)
        XCTAssertNil(med.colorHex)
        XCTAssertNil(med.endDate)
        XCTAssertNil(med.instructions)

        // New v4 attribute (lead-time) also defaults to nil on the migrated row, and round-trips.
        XCTAssertNil(med.leadTimeMinutes, "v4 leadTimeMinutes defaults to nil — additive/lightweight")
        med.leadTimeMinutes = 15
        try ctx.save()
        let reMed = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Medicine>()).first)
        XCTAssertEqual(reMed.leadTimeMinutes, 15, "lead-time persists after being set")

        // The new Note entity exists and is usable in the migrated store.
        ctx.insert(Note(text: "post-migration note"))
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Note>()).count, 1)
    }

    /// BUG 1 migration: a store at V4 (the shape before `quantity`) must upgrade to V5 lightweight —
    /// data preserved, the new `quantity` defaults to nil, and it round-trips after being set.
    func testUpgradeFromV4StoreDefaultsQuantityToNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dose-migrate-v4-\(UUID().uuidString).store")
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + s) } }

        let medID = UUID()

        // 1) Write a store under the V4 (pre-quantity) schema — Medicine has leadTimeMinutes, no quantity.
        do {
            let v4Schema = Schema([DoseSchemaV4.Medicine.self, DoseSchemaV4.DoseTime.self,
                                   DoseSchemaV4.DoseLog.self, DoseSchemaV4.Note.self])
            let v4 = try ModelContainer(for: v4Schema, configurations: [ModelConfiguration(schema: v4Schema, url: url)])
            let ctx = ModelContext(v4)
            let med = DoseSchemaV4.Medicine(id: medID, name: "Amoxicillin", dosage: "500 mg", form: "capsule",
                                            trustStateRaw: "confirmed", isActive: true, createdAt: .now,
                                            instructions: "with food", leadTimeMinutes: 15)
            med.doseTimes = [DoseSchemaV4.DoseTime(hour: 9, minute: 0, weekdays: [2, 4, 6])]
            ctx.insert(med)
            try ctx.save()
        }

        // 2) Open the SAME file with the CURRENT schema (V5) + the migration plan (… → V5).
        let current = try ModelContainer(for: DoseStore.currentSchema, migrationPlan: DoseMigrationPlan.self,
                                         configurations: [ModelConfiguration(schema: DoseStore.currentSchema, url: url)])
        let ctx = ModelContext(current)

        let meds = try ctx.fetch(FetchDescriptor<Medicine>())
        XCTAssertEqual(meds.count, 1, "the medicine survived the V4 → V5 upgrade")
        let med = try XCTUnwrap(meds.first)
        XCTAssertEqual(med.id, medID)
        XCTAssertEqual(med.name, "Amoxicillin")
        XCTAssertEqual(med.instructions, "with food", "existing v3/v4 attributes preserved")
        XCTAssertEqual(med.leadTimeMinutes, 15, "existing v4 attribute preserved")
        XCTAssertEqual(med.doseTimes.first?.weekdays, [2, 4, 6], "schedule preserved")

        // New v5 attribute defaults to nil on the migrated row — the migration-safety contract.
        XCTAssertNil(med.quantity, "v5 quantity defaults to nil — additive/lightweight")

        // …and round-trips once set.
        med.quantity = "100 ml"
        try ctx.save()
        let reMed = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Medicine>()).first)
        XCTAssertEqual(reMed.quantity, "100 ml", "quantity persists after being set")
    }
}
