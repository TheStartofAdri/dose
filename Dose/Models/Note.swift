import Foundation
import SwiftData

/// A plain-text note, stored locally like everything else. Deliberately minimal — free text only,
/// no symptom tracking / severity / categories / trends (scope discipline: Dose is a medication
/// reminder, not a health platform). A note's text can be explicitly sent through the existing
/// parse-medication path to draft a medicine, but a note never becomes a medicine on its own.
@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String = "", createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}
