import Foundation
import SwiftData
import os

/// The single place an `Appointment` is written — like `MetricWriter` for metrics. Trims text fields,
/// throws on a save failure (never a silent success), and re-arms notifications so a new/edited
/// appointment's reminder is scheduled promptly rather than only on the next foreground.
@MainActor
enum AppointmentWriter {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.thestartofadri.dose",
                                       category: "appointments")

    @discardableResult
    static func create(title: String, providerName: String?, location: String?, startsAt: Date,
                       durationMinutes: Int?, notes: String?, reminderLeadMinutes: Int?,
                       iconName: String? = "calendar", colorHex: String? = nil,
                       into context: ModelContext) throws -> Appointment {
        let appt = Appointment(title: title.trimmingCharacters(in: .whitespaces),
                               providerName: cleaned(providerName), location: cleaned(location),
                               startsAt: startsAt, durationMinutes: durationMinutes, notes: cleaned(notes),
                               reminderLeadMinutes: reminderLeadMinutes, iconName: iconName, colorHex: colorHex)
        context.insert(appt)
        try save(context)
        return appt
    }

    /// Apply edited values to an existing appointment and persist.
    static func update(_ appt: Appointment, title: String, providerName: String?, location: String?,
                       startsAt: Date, durationMinutes: Int?, notes: String?, reminderLeadMinutes: Int?,
                       into context: ModelContext) throws {
        appt.title = title.trimmingCharacters(in: .whitespaces)
        appt.providerName = cleaned(providerName)
        appt.location = cleaned(location)
        appt.startsAt = startsAt
        appt.durationMinutes = durationMinutes
        appt.notes = cleaned(notes)
        appt.reminderLeadMinutes = reminderLeadMinutes
        try save(context)
    }

    static func delete(_ appt: Appointment, from context: ModelContext) throws {
        context.delete(appt)
        try save(context)
    }

    private static func cleaned(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private static func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            logger.error("Failed to save appointment change: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
