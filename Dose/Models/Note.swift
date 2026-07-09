import Foundation
import SwiftData

/// Category tags a note can carry (v6). The note stores raw strings in `Note.tags`; this enum is the
/// UI-facing, ordered set. Deliberately a small fixed vocabulary — Dose is a reminder, not a symptom
/// tracker, so tags organize notes without turning them into structured health data.
enum NoteTag: String, Codable, CaseIterable, Sendable, Identifiable {
    case sideEffects = "Side Effects"
    case symptoms = "Symptoms"
    case bloodPressure = "Blood Pressure"
    case doctorVisit = "Doctor Visit"
    case mood = "Mood"
    case general = "General"

    var id: String { rawValue }
}

/// A note, stored locally like everything else. Free text plus (v6) optional tags, an optional link to
/// a medicine, and photo attachments. A note's text can still be explicitly sent through the parse
/// path to draft a medicine, but a note never becomes a medicine on its own.
@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date

    // New in v6 — all additive/defaulted so an existing (v5) store migrates in place (lightweight).
    /// Free-form category tags (raw `NoteTag` values). Empty = untagged.
    var tags: [String] = []
    /// Optional link to the medicine this note is about — by id, NOT a relationship, so a note (like a
    /// `DoseLog`) survives the medicine's deletion. nil = not linked to any medicine.
    var medicineID: UUID?
    /// Attached photos — image bytes are external-stored and cascade-deleted with the note.
    @Relationship(deleteRule: .cascade, inverse: \NotePhoto.note) var photos: [NotePhoto] = []

    /// The stored raw tags resolved to the typed enum (unknown/legacy raw values are dropped).
    var resolvedTags: [NoteTag] { tags.compactMap(NoteTag.init(rawValue:)) }

    init(id: UUID = UUID(), text: String = "", createdAt: Date = .now,
         tags: [String] = [], medicineID: UUID? = nil, photos: [NotePhoto] = []) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.tags = tags
        self.medicineID = medicineID
        self.photos = photos
    }
}

/// A photo attached to a `Note` (v6). Image bytes are kept OUT of the main store file
/// (`.externalStorage`) so a store fetch stays light, and the row is cascade-deleted with its note.
@Model
final class NotePhoto {
    @Attribute(.unique) var id: UUID
    @Attribute(.externalStorage) var imageData: Data
    var createdAt: Date
    var note: Note?

    init(id: UUID = UUID(), imageData: Data, createdAt: Date = .now, note: Note? = nil) {
        self.id = id
        self.imageData = imageData
        self.createdAt = createdAt
        self.note = note
    }
}
