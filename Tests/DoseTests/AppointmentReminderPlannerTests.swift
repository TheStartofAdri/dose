import XCTest
@testable import Dose

/// The pure appointment-reminder planner: arms one reminder per upcoming appointment at (start − lead),
/// skips reminders-off / elapsed windows, sorts soonest-first, and respects the reserve budget.
final class AppointmentReminderPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func snap(_ offsetHours: Double, lead: Int?, title: String = "Visit") -> AppointmentSnapshot {
        AppointmentSnapshot(id: UUID(), title: title, subtitle: nil,
                            startsAt: now.addingTimeInterval(offsetHours * 3600), reminderLeadMinutes: lead)
    }

    func testArmsReminderAtStartMinusLead() {
        let r = AppointmentReminderPlanner.reminders([snap(48, lead: 1440)], now: now)   // 2 days out, day-before
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r.first?.fireDate, now.addingTimeInterval(24 * 3600), "fires 24h before a 48h-out visit")
        XCTAssertEqual(r.first?.startsAt, now.addingTimeInterval(48 * 3600))
    }

    func testSkipsWhenRemindersOff() {
        XCTAssertTrue(AppointmentReminderPlanner.reminders([snap(48, lead: nil)], now: now).isEmpty)
    }

    func testSkipsElapsedLeadWindow() {
        // 1h out, day-before lead → the fire time is already in the past → nothing to schedule.
        XCTAssertTrue(AppointmentReminderPlanner.reminders([snap(1, lead: 1440)], now: now).isEmpty)
    }

    func testSortedSoonestFirstAndCappedAtReserve() {
        let appts = (1...20).map { snap(Double($0) * 24, lead: 60, title: "A\($0)") }   // all future
        let r = AppointmentReminderPlanner.reminders(appts, now: now)
        XCTAssertEqual(r.count, AppointmentReminderPlanner.maxReminders, "capped at the reserve")
        XCTAssertEqual(r.map(\.fireDate), r.map(\.fireDate).sorted(), "soonest first")
    }

    func testZeroBudgetYieldsNothing() {
        XCTAssertTrue(AppointmentReminderPlanner.reminders([snap(48, lead: 60)], now: now, budget: 0).isEmpty)
    }

    func testDeterministicIDPerAppointment() {
        let s = snap(48, lead: 60)
        XCTAssertEqual(AppointmentReminderPlanner.reminders([s], now: now).first?.id,
                       AppointmentReminderPlanner.id(s.id))
    }
}
