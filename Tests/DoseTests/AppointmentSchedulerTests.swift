import XCTest
import SwiftData
@testable import Dose

/// The scheduler wires appointment reminders into `reschedule` alongside doses, using the `addPending`
/// seam to capture what's submitted without the live notification center. Fail-before: `reschedule`
/// had no appointments parameter, so no appointment reminder was ever scheduled.
@MainActor
final class AppointmentSchedulerTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = DoseStore.currentSchema
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    private func capture(_ body: () -> Void) -> [String] {
        var ids: [String] = []
        let prev = NotificationScheduler.shared.addPending
        NotificationScheduler.shared.addPending = { ids.append($0.identifier) }
        defer { NotificationScheduler.shared.addPending = prev }
        body()
        return ids
    }

    func testAppointmentReminderIsScheduled() throws {
        let ctx = try makeContext()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let appt = Appointment(title: "Cardiology", startsAt: now.addingTimeInterval(48 * 3600), reminderLeadMinutes: 1440)
        ctx.insert(appt); try ctx.save()
        let ids = capture {
            NotificationScheduler.shared.reschedule(medicines: [], logs: [], appointments: [appt],
                                                    escalationEnabled: false, now: now)
        }
        XCTAssertTrue(ids.contains(AppointmentReminderPlanner.id(appt.id)), "appointment reminder submitted")
    }

    func testRemindersOffAppointmentNotScheduled() throws {
        let ctx = try makeContext()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let appt = Appointment(title: "Dentist", startsAt: now.addingTimeInterval(48 * 3600), reminderLeadMinutes: nil)
        ctx.insert(appt); try ctx.save()
        let ids = capture {
            NotificationScheduler.shared.reschedule(medicines: [], logs: [], appointments: [appt],
                                                    escalationEnabled: false, now: now)
        }
        XCTAssertFalse(ids.contains(AppointmentReminderPlanner.id(appt.id)), "no reminder when reminders are off")
    }

    /// Doses and appointment reminders are scheduled together — neither the dose rebuild nor the
    /// appointment rebuild wipes the other (they share one `reschedule` pass).
    func testDosesAndAppointmentsCoexist() throws {
        let ctx = try makeContext()
        let now = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date())!
        let med = Medicine(name: "Aspirin", trustState: .confirmed, isActive: true)
        med.doseTimes = [DoseTime(hour: 9, minute: 0)]   // daily → a future 09:00 slot today
        ctx.insert(med)
        let appt = Appointment(title: "Check-up", startsAt: now.addingTimeInterval(72 * 3600), reminderLeadMinutes: 1440)
        ctx.insert(appt); try ctx.save()
        let ids = capture {
            NotificationScheduler.shared.reschedule(medicines: [med], logs: [], appointments: [appt],
                                                    escalationEnabled: false, now: now)
        }
        XCTAssertTrue(ids.contains(AppointmentReminderPlanner.id(appt.id)), "appointment reminder present")
        XCTAssertTrue(ids.contains { $0.hasPrefix("ontime.") }, "dose reminders present alongside")
    }
}
