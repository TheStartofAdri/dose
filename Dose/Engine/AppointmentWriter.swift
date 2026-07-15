import Foundation
import SwiftData
import os

enum AppointmentWriterError: Error, Equatable { case emptyTitle }

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
        let appt = Appointment(title: try requireTitle(title),
                               providerName: cleaned(providerName), location: cleaned(location),
                               startsAt: startsAt, durationMinutes: durationMinutes, notes: cleaned(notes),
                               reminderLeadMinutes: normalizedLead(reminderLeadMinutes),
                               iconName: iconName, colorHex: colorHex)
        context.insert(appt)
        try save(context)
        return appt
    }

    /// Apply edited values to an existing appointment and persist.
    static func update(_ appt: Appointment, title: String, providerName: String?, location: String?,
                       startsAt: Date, durationMinutes: Int?, notes: String?, reminderLeadMinutes: Int?,
                       into context: ModelContext) throws {
        appt.title = try requireTitle(title)
        appt.providerName = cleaned(providerName)
        appt.location = cleaned(location)
        appt.startsAt = startsAt
        appt.durationMinutes = durationMinutes
        appt.notes = cleaned(notes)
        appt.reminderLeadMinutes = normalizedLead(reminderLeadMinutes)
        try save(context)
    }

    /// A title is required — a blank one would produce an empty-title notification. The UI already
    /// disables Save on empty, but the writer is the invariant boundary.
    private static func requireTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppointmentWriterError.emptyTitle }
        return trimmed
    }

    /// A reminder lead can never be negative (that would fire a reminder AFTER the appointment). Clamp to
    /// 0 (= at the time); nil stays nil (no reminder).
    private static func normalizedLead(_ lead: Int?) -> Int? { lead.map { max(0, $0) } }

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
        reschedule(context)
    }

    /// Re-arm notifications after an appointment write so its reminder is scheduled promptly (not only on
    /// the next foreground). Mirrors `MedicineWriter.persist`: fetch the full store state and funnel
    /// through the single `reschedule` path, which re-plans doses AND appointment reminders together.
    private static func reschedule(_ context: ModelContext) {
        let escalationEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.escalationEnabled)
        let meds = (try? context.fetch(FetchDescriptor<Medicine>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        let appts = (try? context.fetch(FetchDescriptor<Appointment>())) ?? []
        NotificationScheduler.shared.reschedule(medicines: meds, logs: logs, appointments: appts,
                                                escalationEnabled: escalationEnabled)
    }
}
