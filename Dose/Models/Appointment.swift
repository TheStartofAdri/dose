import Foundation
import SwiftData

/// A scheduled healthcare appointment the user wants to remember and prepare for (v9). Unlike Medicine,
/// an appointment is a single point in time, so there's no event-log half — it's a lightweight definition.
/// A reminder is armed from `startsAt` minus `reminderLeadMinutes`, mirroring how a dose arms from its slot.
@Model
final class Appointment {
    @Attribute(.unique) var id: UUID
    var title: String
    /// e.g. "Dr. Smith", "City Cardiology" — the person or clinic being seen.
    var providerName: String?
    var location: String?
    var startsAt: Date
    var durationMinutes: Int?
    var notes: String?
    /// Minutes before `startsAt` to remind; nil = no reminder. (1440 = the day before, 60 = an hour before.)
    var reminderLeadMinutes: Int?
    var iconName: String?
    var colorHex: String?
    var createdAt: Date

    init(id: UUID = UUID(), title: String, providerName: String? = nil, location: String? = nil,
         startsAt: Date, durationMinutes: Int? = nil, notes: String? = nil,
         reminderLeadMinutes: Int? = 1440, iconName: String? = nil, colorHex: String? = nil,
         createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.providerName = providerName
        self.location = location
        self.startsAt = startsAt
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.reminderLeadMinutes = reminderLeadMinutes
        self.iconName = iconName
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

extension Appointment {
    /// Whether the appointment's start time has already passed.
    func isPast(now: Date = .now) -> Bool { startsAt < now }

    /// The moment a reminder should fire, or nil when reminders are off or the fire time is already past
    /// (a notification can only be scheduled for the future). Pure given an explicit `now`.
    func reminderFireDate(now: Date = .now) -> Date? {
        guard let lead = reminderLeadMinutes else { return nil }
        let fire = startsAt.addingTimeInterval(-Double(lead) * 60)
        return fire > now ? fire : nil
    }

    /// A one-line subtitle for a row: provider · location, whichever are present.
    var subtitle: String? {
        [providerName, location].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    /// Upcoming appointments (start time still in the future), soonest first — drives the list + Today.
    static func upcoming(_ appointments: [Appointment], now: Date = .now) -> [Appointment] {
        appointments.filter { !$0.isPast(now: now) }.sorted { $0.startsAt < $1.startsAt }
    }

    /// Past appointments, most recent first.
    static func past(_ appointments: [Appointment], now: Date = .now) -> [Appointment] {
        appointments.filter { $0.isPast(now: now) }.sorted { $0.startsAt > $1.startsAt }
    }

    /// The next upcoming appointment, if any — what Today surfaces.
    static func next(_ appointments: [Appointment], now: Date = .now) -> Appointment? {
        upcoming(appointments, now: now).first
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
