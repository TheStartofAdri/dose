import Foundation
import SwiftData

/// A medicine the user tracks. The source of truth lives here in SwiftData. A `Medicine` always
/// has a name (unlike a `DraftMedication`). Only `trustState == .confirmed` instances are allowed
/// to drive the Today screen and notifications.
@Model
final class Medicine {
    @Attribute(.unique) var id: UUID
    var name: String
    var dosage: String?
    var form: String?

    /// Stored as a raw string for predictable persistence; use `trustState` to read/write.
    var trustStateRaw: String
    var isActive: Bool
    var createdAt: Date

    // New in v3 — all optional so an existing (v2) store migrates in place without a default-value
    // crash (Code=134110). nil = "not set", and each has a sensible fallback at the display layer.
    /// SF Symbol name for the medicine's icon (nil → a default pill icon).
    var iconName: String?
    /// Hex string ("#RRGGBB") for the medicine's accent colour (nil → a default tint).
    var colorHex: String?
    /// Last day of treatment, inclusive. nil = ongoing / no end. After this day the medicine stops
    /// scheduling reminders and is out of the adherence/streak window (post-end days are neutral).
    var endDate: Date?
    /// Free-text usage note shown at take time and on detail (e.g. "take with food"). nil → nothing.
    var instructions: String?

    // New in v4 — optional so an existing (v3) store migrates in place (lightweight). nil = no
    // heads-up; a value N means schedule an EXTRA reminder N minutes before each dose. Off by default.
    /// Minutes-before-dose for an optional "heads-up" reminder (nil/0 → none; e.g. 5/10/15/30).
    var leadTimeMinutes: Int?

    // New in v5 — optional so an existing (v4) store migrates in place (lightweight). nil = not set.
    /// Free-text pack size / quantity (e.g. "100 ml", "30 tablets"). nil → not shown on detail.
    var quantity: String?

    // New in v7 — refill / stock tracking, all optional/defaulted → lightweight migration. Stock is
    // DERIVED, never mutated per-take (so Undo stays consistent, matching how adherence/streak derive
    // from `DoseLog`): remaining = unitsAtRefill − unitsPerDose × (taken logs on/after refillDate).
    /// Units in stock recorded at the last refill. nil = not tracking refills for this medicine.
    var unitsAtRefill: Int?
    /// When `unitsAtRefill` was captured — consumption counts taken logs on/after this instant. nil = unset.
    var refillDate: Date?
    /// Units consumed per dose (e.g. 2 tablets). Defaults to 1.
    var unitsPerDose: Int = 1
    /// Remind to refill when the projected days-of-supply falls to/below this. nil = no refill reminder.
    var refillThresholdDays: Int?

    // New in v10 — optional/defaulted → lightweight. When the dose-time RULES were last edited. Adherence
    // and streak reconstruct PAST expected slots from the CURRENT rules; without this, editing a schedule
    // injects phantom misses on past days (and breaks the streak). Days before this instant are scored
    // from the actual take/skip logs only — no miss reconstruction. nil = never edited (score all history).
    var scheduleChangedAt: Date?

    /// Recurring rules only — each `DoseTime` carries no status. Cascade-deleted with the medicine.
    @Relationship(deleteRule: .cascade, inverse: \DoseTime.medicine)
    var doseTimes: [DoseTime]

    var trustState: TrustState {
        get { TrustState(rawValue: trustStateRaw) ?? .draft }
        set { trustStateRaw = newValue.rawValue }
    }

    /// The ONE base filter every medicine-list surface applies — only confirmed medicines the user is
    /// actively taking. Today, History, Export report, This week, and the notification scheduler all read
    /// through this, so they can never disagree about which medicines exist. Archived (`isActive == false`)
    /// and any non-confirmed medicine is excluded everywhere (v1: no "include archived" path — keeps the
    /// surfaces consistent and never offers an archived med in the doctor report as if it were current).
    static func activeConfirmed(_ medicines: [Medicine]) -> [Medicine] {
        medicines.filter { $0.isActive && $0.trustState == .confirmed }
    }

    /// The complement: confirmed medicines the user has archived (set inactive). The only surface that
    /// shows these is the Archived list, where they can be unarchived or permanently deleted.
    static func archived(_ medicines: [Medicine]) -> [Medicine] {
        medicines.filter { !$0.isActive && $0.trustState == .confirmed }
    }

    init(
        id: UUID = UUID(),
        name: String,
        dosage: String? = nil,
        form: String? = nil,
        trustState: TrustState = .draft,
        isActive: Bool = true,
        createdAt: Date = .now,
        iconName: String? = nil,
        colorHex: String? = nil,
        endDate: Date? = nil,
        instructions: String? = nil,
        leadTimeMinutes: Int? = nil,
        quantity: String? = nil,
        unitsAtRefill: Int? = nil,
        refillDate: Date? = nil,
        unitsPerDose: Int = 1,
        refillThresholdDays: Int? = nil,
        scheduleChangedAt: Date? = nil,
        doseTimes: [DoseTime] = []
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.form = form
        self.trustStateRaw = trustState.rawValue
        self.isActive = isActive
        self.createdAt = createdAt
        self.iconName = iconName
        self.colorHex = colorHex
        self.endDate = endDate
        self.instructions = instructions
        self.leadTimeMinutes = leadTimeMinutes
        self.quantity = quantity
        self.unitsAtRefill = unitsAtRefill
        self.refillDate = refillDate
        self.unitsPerDose = unitsPerDose
        self.refillThresholdDays = refillThresholdDays
        self.scheduleChangedAt = scheduleChangedAt
        self.doseTimes = doseTimes
    }
}
