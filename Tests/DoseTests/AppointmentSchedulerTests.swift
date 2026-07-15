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

    /// The digest is one MORE pending request beyond the dose planner + appointment reservation. With a
    /// saturating schedule (far more dose occurrences than the cap) plus an appointment, the total must
    /// still be ≤ 64. Fail-before: `doseBudget = 64 − apptCount` left the digest uncounted → 65 submitted.
    func testTotalPendingNeverExceeds64WithAppointmentAndDigest() throws {
        let ctx = try makeContext()
        let now = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: Date())!
        let med = Medicine(name: "Many", trustState: .confirmed, isActive: true)
        med.doseTimes = (0..<12).map { DoseTime(hour: $0, minute: 0) }   // 12/day × 7d = ~84 occurrences ≫ 64
        ctx.insert(med)
        let appt = Appointment(title: "Visit", startsAt: now.addingTimeInterval(48 * 3600), reminderLeadMinutes: 1440)
        ctx.insert(appt); try ctx.save()
        let ids = capture {
            NotificationScheduler.shared.reschedule(medicines: [med], logs: [], appointments: [appt],
                                                    escalationEnabled: false, now: now)
        }
        XCTAssertLessThanOrEqual(Set(ids).count, NotificationPlanner.maxPending,
                                 "doses + appointment + digest (+sentinel) never exceed the 64-pending cap")
        XCTAssertTrue(ids.contains(AppointmentReminderPlanner.id(appt.id)), "appointment reminder still armed")
        XCTAssertTrue(ids.contains(NotificationScheduler.weeklyDigestID), "digest still armed")
    }
}
