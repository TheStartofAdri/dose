import Foundation

/// A scheduled appointment reminder → a one-shot local notification that fires `reminderLeadMinutes`
/// before the visit. Plain (no dose category): a tap is pure navigation, never a dose action.
struct AppointmentReminder: Sendable, Hashable {
    let id: String
    let appointmentID: UUID
    let title: String
    let subtitle: String?
    let fireDate: Date       // when the notification fires (startsAt − lead)
    let startsAt: Date       // the appointment itself
}

/// Pure planner for appointment reminders. Kept separate from the dose `NotificationPlanner` because
/// appointments are their own domain — but the scheduler reserves their (bounded) count from the shared
/// 64-slot iOS cap so doses and appointments together can never exceed it. One reminder per upcoming
/// appointment whose lead-time hasn't already elapsed; soonest-first; capped at `maxReminders`.
enum AppointmentReminderPlanner {
    /// A modest reserve: realistically a user has a handful of upcoming appointments, and doses must keep
    /// the lion's share of the 64-slot cap. Soonest reminders win when there are more than this.
    static let maxReminders = 16

    /// The deterministic id for an appointment's reminder — rebuilt wholesale by every reschedule (like
    /// the refill/digest reminders), so it's never orphaned and needs no per-slot cancellation.
    static func id(_ appointmentID: UUID) -> String { "appt.\(appointmentID.uuidString)" }

    static func reminders(_ appointments: [AppointmentSnapshot], now: Date,
                          budget: Int = maxReminders) -> [AppointmentReminder] {
        guard budget > 0 else { return [] }
        var out: [AppointmentReminder] = []
        for appt in appointments {
            guard let lead = appt.reminderLeadMinutes else { continue }        // reminders off
            let fire = appt.startsAt.addingTimeInterval(-Double(lead) * 60)
            guard fire > now else { continue }                                 // lead window already elapsed
            out.append(AppointmentReminder(id: id(appt.id), appointmentID: appt.id, title: appt.title,
                                           subtitle: appt.subtitle, fireDate: fire, startsAt: appt.startsAt))
        }
        return Array(out.sorted { $0.fireDate < $1.fireDate }.prefix(budget))
    }
}
