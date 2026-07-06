import Foundation
import SwiftData

// MARK: - V1: the very first shipped schema (DoseTime had no interval/anchor/days-of-month).
//
// Faithful frozen copies of the V1 models so the migration plan can recognize an existing on-disk
// store as V1 and migrate it forward. Nested in the enum so their entity names ("Medicine",
// "DoseTime", "DoseLog") match the shipped store while not clashing with the current top-level models.

enum DoseSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Medicine.self, DoseTime.self, DoseLog.self] }

    @Model final class Medicine {
        @Attribute(.unique) var id: UUID
        var name: String
        var dosage: String?
        var form: String?
        var trustStateRaw: String
        var isActive: Bool
        var createdAt: Date
        @Relationship(deleteRule: .cascade, inverse: \DoseTime.medicine) var doseTimes: [DoseTime]

        init(id: UUID = UUID(), name: String, dosage: String? = nil, form: String? = nil,
             trustStateRaw: String = "draft", isActive: Bool = true, createdAt: Date = .now,
             doseTimes: [DoseTime] = []) {
            self.id = id
            self.name = name
            self.dosage = dosage
            self.form = form
            self.trustStateRaw = trustStateRaw
            self.isActive = isActive
            self.createdAt = createdAt
            self.doseTimes = doseTimes
        }
    }

    @Model final class DoseTime {
        var hour: Int
        var minute: Int
        var weekdays: [Int]
        var medicine: Medicine?

        init(hour: Int, minute: Int, weekdays: [Int] = [], medicine: Medicine? = nil) {
            self.hour = hour
            self.minute = minute
            self.weekdays = weekdays
            self.medicine = medicine
        }
    }

    @Model final class DoseLog {
        @Attribute(.unique) var id: UUID
        var medicineID: UUID
        var medicineName: String
        var dosage: String?
        var scheduledFor: Date
        var actionRaw: String
        var actionedAt: Date

        init(id: UUID = UUID(), medicineID: UUID, medicineName: String, dosage: String? = nil,
             scheduledFor: Date, actionRaw: String, actionedAt: Date = .now) {
            self.id = id
            self.medicineID = medicineID
            self.medicineName = medicineName
            self.dosage = dosage
            self.scheduledFor = scheduledFor
            self.actionRaw = actionRaw
            self.actionedAt = actionedAt
        }
    }
}

// MARK: - V2: the previously-shipped schema (DoseTime gained interval/anchor/days-of-month).
//
// Frozen faithful copies of the 2.0.0 shape — this is what an existing on-device store looks like
// today. (Previously this enum pointed at the live top-level models, which meant it wasn't actually
// frozen; adding new attributes to the live models would have silently changed the "2.0.0" schema
// and broken in-place migration. It is now a real frozen snapshot.)

enum DoseSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Medicine.self, DoseTime.self, DoseLog.self] }

    @Model final class Medicine {
        @Attribute(.unique) var id: UUID
        var name: String
        var dosage: String?
        var form: String?
        var trustStateRaw: String
        var isActive: Bool
        var createdAt: Date
        @Relationship(deleteRule: .cascade, inverse: \DoseTime.medicine) var doseTimes: [DoseTime]

        init(id: UUID = UUID(), name: String, dosage: String? = nil, form: String? = nil,
             trustStateRaw: String = "draft", isActive: Bool = true, createdAt: Date = .now,
             doseTimes: [DoseTime] = []) {
            self.id = id
            self.name = name
            self.dosage = dosage
            self.form = form
            self.trustStateRaw = trustStateRaw
            self.isActive = isActive
            self.createdAt = createdAt
            self.doseTimes = doseTimes
        }
    }

    @Model final class DoseTime {
        var hour: Int
        var minute: Int
        var weekdays: [Int] = []
        var intervalDays: Int = 0
        var anchorDate: Date?
        var daysOfMonth: [Int] = []
        var medicine: Medicine?

        init(hour: Int, minute: Int, weekdays: [Int] = [], intervalDays: Int = 0,
             anchorDate: Date? = nil, daysOfMonth: [Int] = [], medicine: Medicine? = nil) {
            self.hour = hour
            self.minute = minute
            self.weekdays = weekdays
            self.intervalDays = intervalDays
            self.anchorDate = anchorDate
            self.daysOfMonth = daysOfMonth
            self.medicine = medicine
        }
    }

    @Model final class DoseLog {
        @Attribute(.unique) var id: UUID
        var medicineID: UUID
        var medicineName: String
        var dosage: String?
        var scheduledFor: Date
        var actionRaw: String
        var actionedAt: Date

        init(id: UUID = UUID(), medicineID: UUID, medicineName: String, dosage: String? = nil,
             scheduledFor: Date, actionRaw: String, actionedAt: Date = .now) {
            self.id = id
            self.medicineID = medicineID
            self.medicineName = medicineName
            self.dosage = dosage
            self.scheduledFor = scheduledFor
            self.actionRaw = actionRaw
            self.actionedAt = actionedAt
        }
    }
}

// MARK: - V3: the previously-shipped schema — Medicine gained iconName / colorHex / endDate /
// instructions (all optional), and a new `Note` entity was added. Frozen faithful copies of the
// 3.0.0 shape (NO leadTimeMinutes), so adding attributes to the live models can't silently change
// "3.0.0" and break in-place migration — the same discipline applied to V1/V2 above.

enum DoseSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [Medicine.self, DoseTime.self, DoseLog.self, Note.self] }

    @Model final class Medicine {
        @Attribute(.unique) var id: UUID
        var name: String
        var dosage: String?
        var form: String?
        var trustStateRaw: String
        var isActive: Bool
        var createdAt: Date
        var iconName: String?
        var colorHex: String?
        var endDate: Date?
        var instructions: String?
        @Relationship(deleteRule: .cascade, inverse: \DoseTime.medicine) var doseTimes: [DoseTime]

        init(id: UUID = UUID(), name: String, dosage: String? = nil, form: String? = nil,
             trustStateRaw: String = "draft", isActive: Bool = true, createdAt: Date = .now,
             iconName: String? = nil, colorHex: String? = nil, endDate: Date? = nil,
             instructions: String? = nil, doseTimes: [DoseTime] = []) {
            self.id = id
            self.name = name
            self.dosage = dosage
            self.form = form
            self.trustStateRaw = trustStateRaw
            self.isActive = isActive
            self.createdAt = createdAt
            self.iconName = iconName
            self.colorHex = colorHex
            self.endDate = endDate
            self.instructions = instructions
            self.doseTimes = doseTimes
        }
    }

    @Model final class DoseTime {
        var hour: Int
        var minute: Int
        var weekdays: [Int] = []
        var intervalDays: Int = 0
        var anchorDate: Date?
        var daysOfMonth: [Int] = []
        var medicine: Medicine?

        init(hour: Int, minute: Int, weekdays: [Int] = [], intervalDays: Int = 0,
             anchorDate: Date? = nil, daysOfMonth: [Int] = [], medicine: Medicine? = nil) {
            self.hour = hour
            self.minute = minute
            self.weekdays = weekdays
            self.intervalDays = intervalDays
            self.anchorDate = anchorDate
            self.daysOfMonth = daysOfMonth
            self.medicine = medicine
        }
    }

    @Model final class DoseLog {
        @Attribute(.unique) var id: UUID
        var medicineID: UUID
        var medicineName: String
        var dosage: String?
        var scheduledFor: Date
        var actionRaw: String
        var actionedAt: Date

        init(id: UUID = UUID(), medicineID: UUID, medicineName: String, dosage: String? = nil,
             scheduledFor: Date, actionRaw: String, actionedAt: Date = .now) {
            self.id = id
            self.medicineID = medicineID
            self.medicineName = medicineName
            self.dosage = dosage
            self.scheduledFor = scheduledFor
            self.actionRaw = actionRaw
            self.actionedAt = actionedAt
        }
    }

    @Model final class Note {
        @Attribute(.unique) var id: UUID
        var text: String
        var createdAt: Date

        init(id: UUID = UUID(), text: String = "", createdAt: Date = .now) {
            self.id = id
            self.text = text
            self.createdAt = createdAt
        }
    }
}

// MARK: - V4: the previously-shipped schema — Medicine gained `leadTimeMinutes` (optional). Frozen
// faithful copies of the 4.0.0 shape (NO `quantity`), so adding `quantity` to the live models can't
// silently change "4.0.0" and break in-place migration — the same discipline applied to V1/V2/V3 above.

enum DoseSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] { [Medicine.self, DoseTime.self, DoseLog.self, Note.self] }

    @Model final class Medicine {
        @Attribute(.unique) var id: UUID
        var name: String
        var dosage: String?
        var form: String?
        var trustStateRaw: String
        var isActive: Bool
        var createdAt: Date
        var iconName: String?
        var colorHex: String?
        var endDate: Date?
        var instructions: String?
        var leadTimeMinutes: Int?
        @Relationship(deleteRule: .cascade, inverse: \DoseTime.medicine) var doseTimes: [DoseTime]

        init(id: UUID = UUID(), name: String, dosage: String? = nil, form: String? = nil,
             trustStateRaw: String = "draft", isActive: Bool = true, createdAt: Date = .now,
             iconName: String? = nil, colorHex: String? = nil, endDate: Date? = nil,
             instructions: String? = nil, leadTimeMinutes: Int? = nil, doseTimes: [DoseTime] = []) {
            self.id = id
            self.name = name
            self.dosage = dosage
            self.form = form
            self.trustStateRaw = trustStateRaw
            self.isActive = isActive
            self.createdAt = createdAt
            self.iconName = iconName
            self.colorHex = colorHex
            self.endDate = endDate
            self.instructions = instructions
            self.leadTimeMinutes = leadTimeMinutes
            self.doseTimes = doseTimes
        }
    }

    @Model final class DoseTime {
        var hour: Int
        var minute: Int
        var weekdays: [Int] = []
        var intervalDays: Int = 0
        var anchorDate: Date?
        var daysOfMonth: [Int] = []
        var medicine: Medicine?

        init(hour: Int, minute: Int, weekdays: [Int] = [], intervalDays: Int = 0,
             anchorDate: Date? = nil, daysOfMonth: [Int] = [], medicine: Medicine? = nil) {
            self.hour = hour
            self.minute = minute
            self.weekdays = weekdays
            self.intervalDays = intervalDays
            self.anchorDate = anchorDate
            self.daysOfMonth = daysOfMonth
            self.medicine = medicine
        }
    }

    @Model final class DoseLog {
        @Attribute(.unique) var id: UUID
        var medicineID: UUID
        var medicineName: String
        var dosage: String?
        var scheduledFor: Date
        var actionRaw: String
        var actionedAt: Date

        init(id: UUID = UUID(), medicineID: UUID, medicineName: String, dosage: String? = nil,
             scheduledFor: Date, actionRaw: String, actionedAt: Date = .now) {
            self.id = id
            self.medicineID = medicineID
            self.medicineName = medicineName
            self.dosage = dosage
            self.scheduledFor = scheduledFor
            self.actionRaw = actionRaw
            self.actionedAt = actionedAt
        }
    }

    @Model final class Note {
        @Attribute(.unique) var id: UUID
        var text: String
        var createdAt: Date

        init(id: UUID = UUID(), text: String = "", createdAt: Date = .now) {
            self.id = id
            self.text = text
            self.createdAt = createdAt
        }
    }
}

// MARK: - V5: the current schema — Medicine gained `quantity` (optional → migration-safe). `models`
// are the live top-level types, so V5 always tracks the current app models.

enum DoseSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] { [Medicine.self, DoseTime.self, DoseLog.self, Note.self] }
}

// MARK: - Migration plan: every hop is purely additive with safe defaults / a new entity, so each
// stage is lightweight. V1 → V2 → V3 → V4 → V5.

enum DoseMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [DoseSchemaV1.self, DoseSchemaV2.self, DoseSchemaV3.self, DoseSchemaV4.self, DoseSchemaV5.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: DoseSchemaV1.self, toVersion: DoseSchemaV2.self),
            .lightweight(fromVersion: DoseSchemaV2.self, toVersion: DoseSchemaV3.self),
            .lightweight(fromVersion: DoseSchemaV3.self, toVersion: DoseSchemaV4.self),
            .lightweight(fromVersion: DoseSchemaV4.self, toVersion: DoseSchemaV5.self),
        ]
    }
}

// MARK: - Container factory: never dead-launch on a load/migration failure.

/// How the app's store loaded — so a recovery (which leaves the user looking at an empty list that's
/// indistinguishable from a fresh install) can be SURFACED rather than only NSLog'd. `.normal` is the
/// happy path; the other two mean the previous store was set aside (preserved on disk, never deleted).
enum StoreLoadOutcome: Equatable {
    case normal                 // loaded/migrated cleanly
    case recreatedEmptyStore    // prior store unreadable → set aside, fresh empty store (new data persists)
    case inMemoryFallback       // even recreate failed → in-memory only (new data won't persist this launch)
}

enum DoseStore {
    static var currentSchema: Schema { Schema(versionedSchema: DoseSchemaV5.self) }

    /// The outcome of the most recent `makeContainer()` call, read by `DoseApp` to drive the recovery
    /// notice. `.normal` until proven otherwise.
    static private(set) var lastLoadOutcome: StoreLoadOutcome = .normal

    /// The default on-disk store location (App Support/default.store), shared by `makeContainer`
    /// and the DEBUG legacy-store injectors below so they all operate on the same file.
    static var defaultStoreURL: URL { ModelConfiguration(schema: currentSchema).url }

    /// Builds the app's container. Tries a normal load (running the migration plan); on failure,
    /// logs and recovers — first by moving the unreadable store aside (data preserved on disk, not
    /// wiped) and recreating, then as an absolute last resort an in-memory store so the app still
    /// launches instead of crashing in the user's hands. Records the outcome in `lastLoadOutcome`.
    static func makeContainer() -> ModelContainer {
        let schema = currentSchema
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let (container, outcome) = resolveContainer(
            primary: { try ModelContainer(for: schema, migrationPlan: DoseMigrationPlan.self, configurations: [config]) },
            recreate: { try ModelContainer(for: schema, migrationPlan: DoseMigrationPlan.self, configurations: [config]) },
            inMemory: { try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]) },
            onRecover: { moveStoreAside(config.url) }
        )
        lastLoadOutcome = outcome
        return container
    }

    /// The recovery DECISION, isolated from the real `ModelContainer`/disk wiring so it's unit-testable:
    /// a test injects closures that throw to simulate a load/migration failure without corrupting a real
    /// store. Order: primary → (on failure) onRecover + recreate → (on failure) in-memory last resort.
    static func resolveContainer(
        primary: () throws -> ModelContainer,
        recreate: () throws -> ModelContainer,
        inMemory: () throws -> ModelContainer,
        onRecover: () -> Void
    ) -> (ModelContainer, StoreLoadOutcome) {
        do {
            return (try primary(), .normal)
        } catch {
            NSLog("Dose: store load/migration failed (\(error)). Recovering by moving the store aside.")
            onRecover()
            do {
                return (try recreate(), .recreatedEmptyStore)
            } catch {
                NSLog("Dose: recreate failed (\(error)). Falling back to an in-memory store for this launch.")
                do {
                    return (try inMemory(), .inMemoryFallback)
                } catch {
                    // If even an in-memory store fails the install is unusable regardless; trapping here is acceptable.
                    fatalError("Dose: could not create any ModelContainer: \(error)")
                }
            }
        }
    }

    /// Moves the store (and its -wal/-shm sidecars) aside rather than deleting, so a failed migration
    /// never silently destroys user data — the file is recoverable for support/debugging.
    private static func moveStoreAside(_ url: URL) {
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-wal", "-shm"] {
            let path = url.path + suffix
            guard fm.fileExists(atPath: path) else { continue }
            try? fm.moveItem(atPath: path, toPath: path + ".corrupt-\(stamp)")
        }
    }

    #if DEBUG
    /// Writes a genuine OLD-schema (V1) store with one medicine at the default store location, so a
    /// subsequent normal launch exercises the real V1 → … → current upgrade path.
    static func writeLegacyStoreForTesting() {
        let url = defaultStoreURL
        moveStoreAside(url)
        let v1Schema = Schema([DoseSchemaV1.Medicine.self, DoseSchemaV1.DoseTime.self, DoseSchemaV1.DoseLog.self])
        guard let v1 = try? ModelContainer(for: v1Schema, configurations: [ModelConfiguration(schema: v1Schema, url: url)]) else { return }
        let ctx = ModelContext(v1)
        let med = DoseSchemaV1.Medicine(name: "Legacy Vitamin", dosage: "1000 IU", form: "tablet",
                                        trustStateRaw: "confirmed", isActive: true, createdAt: .now)
        med.doseTimes = [DoseSchemaV1.DoseTime(hour: 8, minute: 0)]
        ctx.insert(med)
        try? ctx.save()
    }

    /// Writes a genuine V2 store (the previously-shipped shape) at the default location, so a normal
    /// launch exercises the real V2 → V3 upgrade — the path an actual on-device store takes now.
    static func writeLegacyStoreV2ForTesting() {
        let url = defaultStoreURL
        moveStoreAside(url)
        let v2Schema = Schema([DoseSchemaV2.Medicine.self, DoseSchemaV2.DoseTime.self, DoseSchemaV2.DoseLog.self])
        guard let v2 = try? ModelContainer(for: v2Schema, configurations: [ModelConfiguration(schema: v2Schema, url: url)]) else { return }
        let ctx = ModelContext(v2)
        let med = DoseSchemaV2.Medicine(name: "Legacy V2 Med", dosage: "5 mg", form: "tablet",
                                        trustStateRaw: "confirmed", isActive: true, createdAt: .now)
        med.doseTimes = [DoseSchemaV2.DoseTime(hour: 9, minute: 0)]   // daily → always on Today
        ctx.insert(med)
        try? ctx.save()
    }
    #endif
}
