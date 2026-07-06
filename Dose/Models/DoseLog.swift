import Foundation
import SwiftData

/// Append-only record of a real action against a scheduled slot. Denormalizes the medicine
/// name/dosage so adherence history and doctor exports survive even after the medicine is deleted —
/// hence there is intentionally **no** relationship to `Medicine` and it is not cascade-deleted.
@Model
final class DoseLog {
    @Attribute(.unique) var id: UUID
    var medicineID: UUID
    var medicineName: String
    var dosage: String?
    var scheduledFor: Date
    var actionRaw: String
    var actionedAt: Date

    var action: DoseAction {
        get { DoseAction(rawValue: actionRaw) ?? .taken }
        set { actionRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        medicineID: UUID,
        medicineName: String,
        dosage: String? = nil,
        scheduledFor: Date,
        action: DoseAction,
        actionedAt: Date = .now
    ) {
        self.id = id
        self.medicineID = medicineID
        self.medicineName = medicineName
        self.dosage = dosage
        self.scheduledFor = scheduledFor
        self.actionRaw = action.rawValue
        self.actionedAt = actionedAt
    }
}
