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

    /// v6 migration: a store at V5 (before Note tags/link/photos and DoseLog.snoozeMinutes) must
    /// upgrade to V6 lightweight — meds/logs/notes preserved, the new fields default (empty/nil), the
    /// new `NotePhoto` external-storage entity is usable, and everything round-trips once set. If the
    /// V5 → V6 hop is NOT actually lightweight-compatible, opening the container below throws and fails
    /// this test (rather than shipping a migration that would move a real user's store aside).
    func testUpgradeFromV5StoreDefaultsNoteAndSnoozeFields() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dose-migrate-v5-\(UUID().uuidString).store")
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + s) } }

        let medID = UUID()
        let noteID = UUID()

        // 1) Write a store under the V5 (pre-v6) schema — Note is text-only; DoseLog has no snoozeMinutes.
        do {
            let v5Schema = Schema([DoseSchemaV5.Medicine.self, DoseSchemaV5.DoseTime.self,
                                   DoseSchemaV5.DoseLog.self, DoseSchemaV5.Note.self])
            let v5 = try ModelContainer(for: v5Schema, configurations: [ModelConfiguration(schema: v5Schema, url: url)])
            let ctx = ModelContext(v5)
            let med = DoseSchemaV5.Medicine(id: medID, name: "Amoxicillin", dosage: "500 mg", form: "capsule",
                                            trustStateRaw: "confirmed", isActive: true, createdAt: .now, quantity: "20 caps")
            med.doseTimes = [DoseSchemaV5.DoseTime(hour: 9, minute: 0, weekdays: [2, 4, 6])]
            ctx.insert(med)
            ctx.insert(DoseSchemaV5.DoseLog(medicineID: medID, medicineName: "Amoxicillin",
                                            scheduledFor: .now, actionRaw: "taken"))
            ctx.insert(DoseSchemaV5.Note(id: noteID, text: "felt fine"))
            try ctx.save()
        }

        // 2) Open the SAME file with the CURRENT schema (V6) + the migration plan (V5 → V6).
        let current = try ModelContainer(for: DoseStore.currentSchema, migrationPlan: DoseMigrationPlan.self,
                                         configurations: [ModelConfiguration(schema: DoseStore.currentSchema, url: url)])
        let ctx = ModelContext(current)

        // Existing data survived the upgrade.
        let med = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Medicine>()).first)
        XCTAssertEqual(med.id, medID)
        XCTAssertEqual(med.quantity, "20 caps", "existing v5 attribute preserved")
        XCTAssertEqual(med.doseTimes.first?.weekdays, [2, 4, 6], "schedule preserved")

        let log = try XCTUnwrap(try ctx.fetch(FetchDescriptor<DoseLog>()).first)
        XCTAssertEqual(log.action, .taken, "existing log preserved")
        XCTAssertNil(log.snoozeMinutes, "v6 snoozeMinutes defaults to nil — additive/lightweight")

        let note = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Note>()).first)
        XCTAssertEqual(note.id, noteID)
        XCTAssertEqual(note.text, "felt fine", "existing note text preserved")
        XCTAssertEqual(note.tags, [], "v6 tags default to empty")
        XCTAssertNil(note.medicineID, "v6 medicineID defaults to nil")
        XCTAssertTrue(note.photos.isEmpty, "v6 photos default to empty")

        // New v6 fields round-trip once set, and the new NotePhoto entity is usable + cascade-linked.
        log.snoozeMinutes = 30
        note.tags = [NoteTag.sideEffects.rawValue]
        note.medicineID = medID
        note.photos = [NotePhoto(imageData: Data([0x01, 0x02, 0x03]))]
        try ctx.save()

        let reNote = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Note>()).first)
        XCTAssertEqual(reNote.tags, ["Side Effects"], "tags persist")
        XCTAssertEqual(reNote.medicineID, medID, "medicine link persists")
        XCTAssertEqual(reNote.photos.count, 1, "attached photo persists (cascade relationship)")
        XCTAssertEqual(reNote.resolvedTags, [.sideEffects], "raw tags resolve to the typed enum")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<DoseLog>()).first?.snoozeMinutes, 30, "snoozeMinutes persists")
    }

    /// Realistic-scale V5 → V6 upgrade (the shape a shipped-5.0.0 user actually has): many medicines,
    /// months of DoseLogs, several notes. Asserts NOTHING is lost, exact counts, a spot-checked med's
    /// fields, and that every new v6 field defaults across the whole store. The container opening at all
    /// with the migration plan proves the hop is lightweight (a non-lightweight change would throw).
    func testUpgradeFromLargeV5StorePreservesEveryRecord() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dose-migrate-bulk-\(UUID().uuidString).store")
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + s) } }

        let medCount = 20, logsPerMed = 40, noteCount = 8
        var medIDs: [UUID] = []

        // 1) Write a realistic V5 store.
        do {
            let v5Schema = Schema([DoseSchemaV5.Medicine.self, DoseSchemaV5.DoseTime.self,
                                   DoseSchemaV5.DoseLog.self, DoseSchemaV5.Note.self])
            let v5 = try ModelContainer(for: v5Schema, configurations: [ModelConfiguration(schema: v5Schema, url: url)])
            let ctx = ModelContext(v5)
            let base = Date(timeIntervalSince1970: 1_700_000_000)
            for m in 0..<medCount {
                let id = UUID(); medIDs.append(id)
                let med = DoseSchemaV5.Medicine(id: id, name: "Med \(m)", dosage: "\(m) mg", form: "tablet",
                                                trustStateRaw: "confirmed", isActive: true, createdAt: base,
                                                quantity: "\(m * 10) tablets")
                med.doseTimes = [DoseSchemaV5.DoseTime(hour: 8, minute: 0)]
                ctx.insert(med)
                for d in 0..<logsPerMed {
                    let slot = base.addingTimeInterval(Double(d) * 86_400 + 8 * 3600)
                    ctx.insert(DoseSchemaV5.DoseLog(medicineID: id, medicineName: "Med \(m)", dosage: "\(m) mg",
                                                    scheduledFor: slot,
                                                    actionRaw: d.isMultiple(of: 3) ? "skipped" : "taken",
                                                    actionedAt: slot.addingTimeInterval(120)))
                }
            }
            for n in 0..<noteCount { ctx.insert(DoseSchemaV5.Note(text: "Note \(n)")) }
            try ctx.save()
        }

        // 2) Open with the CURRENT schema (V6) + the migration plan.
        let current = try ModelContainer(for: DoseStore.currentSchema, migrationPlan: DoseMigrationPlan.self,
                                         configurations: [ModelConfiguration(schema: DoseStore.currentSchema, url: url)])
        let ctx = ModelContext(current)

        // Exact counts — nothing lost.
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Medicine>()).count, medCount, "all medicines preserved")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<DoseLog>()).count, medCount * logsPerMed, "all logs preserved")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Note>()).count, noteCount, "all notes preserved")

        // A spot-checked medicine's pre-existing fields survive intact.
        let med = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Medicine>()).first { $0.id == medIDs[0] })
        XCTAssertEqual(med.name, "Med 0")
        XCTAssertEqual(med.quantity, "0 tablets")
        XCTAssertEqual(med.trustState, .confirmed)
        XCTAssertEqual(med.doseTimes.first?.hour, 8)

        // Every new v6 field defaults across the whole migrated store.
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<DoseLog>()).allSatisfy { $0.snoozeMinutes == nil },
                      "snoozeMinutes defaults nil on every migrated log")
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<Note>()).allSatisfy { $0.tags.isEmpty && $0.medicineID == nil && $0.photos.isEmpty },
                      "tags/medicineID/photos default empty/nil on every migrated note")
    }

    /// A note's photos are cascade-deleted with the note, and deleting a single photo drops the count.
    /// (The relationship-row cleanup is what's statically provable; on-disk external-blob reclamation is
    /// a device-only check — flagged in the pre-merge plan.)
    func testDeletingNoteCascadesToItsPhotos() throws {
        let schema = DoseStore.currentSchema
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let ctx = ModelContext(container)

        let note = Note(text: "with photos")
        note.photos = [NotePhoto(imageData: Data([1])), NotePhoto(imageData: Data([2])), NotePhoto(imageData: Data([3]))]
        ctx.insert(note)
        let keep = Note(text: "keep")
        keep.photos = [NotePhoto(imageData: Data([9]))]
        ctx.insert(keep)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NotePhoto>()).count, 4)

        // Delete one photo from `keep`.
        if let p = keep.photos.first {
            keep.photos.removeAll { $0.id == p.id }
            ctx.delete(p)
        }
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NotePhoto>()).count, 3, "deleting one photo drops the count")

        // Delete the whole note → its 3 photos cascade away.
        ctx.delete(note)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<NotePhoto>()).count, 0, "cascade removed the note's photos")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Note>()).count, 1, "the other note remains")
    }

    /// v9 migration: a store at V8 (before the `Appointment` entity) must upgrade to V9 lightweight —
    /// meds/metrics/entries preserved and the brand-new `Appointment` entity usable in the migrated
    /// store. The container opening at all with the plan proves the V8 → V9 hop is lightweight (a
    /// non-lightweight change would throw here instead of shipping a store-mangling migration).
    func testUpgradeFromV8StorePreservesDataAndAddsAppointments() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dose-migrate-v8-\(UUID().uuidString).store")
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + s) } }

        let medID = UUID()
        let metricID = UUID()

        // 1) Write a store under the V8 (pre-Appointment) schema — meds + a tracked metric with an entry.
        do {
            let v8Schema = Schema(versionedSchema: DoseSchemaV8.self)
            let v8 = try ModelContainer(for: v8Schema, configurations: [ModelConfiguration(schema: v8Schema, url: url)])
            let ctx = ModelContext(v8)
            let med = DoseSchemaV8.Medicine(id: medID, name: "Amoxicillin", dosage: "500 mg", form: "capsule",
                                            trustStateRaw: "confirmed", isActive: true, createdAt: .now)
            med.doseTimes = [DoseSchemaV8.DoseTime(hour: 9, minute: 0, weekdays: [2, 4, 6])]
            ctx.insert(med)
            let metric = DoseSchemaV8.TrackedMetric(id: metricID, name: "Pain", kindRaw: "symptom", valueKindRaw: "severity")
            metric.entries = [DoseSchemaV8.MetricEntry(severity: 6)]
            ctx.insert(metric)
            try ctx.save()
        }

        // 2) Open the SAME file with the CURRENT schema (V9) + the migration plan (V8 → V9).
        let current = try ModelContainer(for: DoseStore.currentSchema, migrationPlan: DoseMigrationPlan.self,
                                         configurations: [ModelConfiguration(schema: DoseStore.currentSchema, url: url)])
        let ctx = ModelContext(current)

        // Existing data survived the upgrade.
        let med = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Medicine>()).first)
        XCTAssertEqual(med.id, medID)
        XCTAssertEqual(med.doseTimes.first?.weekdays, [2, 4, 6], "schedule preserved")
        let metric = try XCTUnwrap(try ctx.fetch(FetchDescriptor<TrackedMetric>()).first)
        XCTAssertEqual(metric.id, metricID)
        XCTAssertEqual(metric.entries.first?.severity, 6, "metric entry preserved")

        // The brand-new Appointment entity is empty after migration, then usable + persists.
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Appointment>()).count, 0, "no appointments in a migrated store")
        let apptID = UUID()
        let starts = Date(timeIntervalSince1970: 1_800_000_000)
        ctx.insert(Appointment(id: apptID, title: "Cardiology follow-up", providerName: "Dr. Smith",
                               location: "City Clinic", startsAt: starts, reminderLeadMinutes: 1440))
        try ctx.save()
        let appt = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Appointment>()).first)
        XCTAssertEqual(appt.id, apptID)
        XCTAssertEqual(appt.title, "Cardiology follow-up")
        XCTAssertEqual(appt.providerName, "Dr. Smith")
        XCTAssertEqual(appt.startsAt, starts, "appointment persists after migration")
    }

    /// v10 migration: a store at V9 (before `Medicine.scheduleChangedAt`) must upgrade to V10 lightweight
    /// — meds/appointments preserved, the new field defaults to nil, and it round-trips once set.
    func testUpgradeFromV9StoreDefaultsScheduleChangedAt() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dose-migrate-v9-\(UUID().uuidString).store")
        defer { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + s) } }

        let medID = UUID()
        do {
            let v9Schema = Schema(versionedSchema: DoseSchemaV9.self)
            let v9 = try ModelContainer(for: v9Schema, configurations: [ModelConfiguration(schema: v9Schema, url: url)])
            let ctx = ModelContext(v9)
            let med = DoseSchemaV9.Medicine(id: medID, name: "Amoxicillin", dosage: "500 mg", form: "capsule",
                                            trustStateRaw: "confirmed", isActive: true, createdAt: .now)
            med.doseTimes = [DoseSchemaV9.DoseTime(hour: 9, minute: 0, weekdays: [2, 4, 6])]
            ctx.insert(med)
            ctx.insert(DoseSchemaV9.Appointment(title: "Follow-up", startsAt: Date(timeIntervalSince1970: 1_800_000_000)))
            try ctx.save()
        }

        let current = try ModelContainer(for: DoseStore.currentSchema, migrationPlan: DoseMigrationPlan.self,
                                         configurations: [ModelConfiguration(schema: DoseStore.currentSchema, url: url)])
        let ctx = ModelContext(current)

        let med = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Medicine>()).first)
        XCTAssertEqual(med.id, medID)
        XCTAssertEqual(med.doseTimes.first?.weekdays, [2, 4, 6], "schedule preserved")
        XCTAssertNil(med.scheduleChangedAt, "v10 scheduleChangedAt defaults to nil — additive/lightweight")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Appointment>()).count, 1, "appointment preserved")

        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        med.scheduleChangedAt = stamp
        try ctx.save()
        XCTAssertEqual(try XCTUnwrap(try ctx.fetch(FetchDescriptor<Medicine>()).first).scheduleChangedAt, stamp,
                       "scheduleChangedAt persists once set")
    }
}
