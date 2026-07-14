import XCTest
@testable import Dose

/// The pure appointment helpers: upcoming/past partitioning, next, reminder fire-time, subtitle.
final class AppointmentTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func appt(_ offsetHours: Double, lead: Int? = 1440,
                      provider: String? = nil, location: String? = nil) -> Appointment {
        Appointment(title: "Visit", providerName: provider, location: location,
                    startsAt: now.addingTimeInterval(offsetHours * 3600), reminderLeadMinutes: lead)
    }

    func testUpcomingIsFutureSortedSoonestFirst() {
        let past = appt(-2), soon = appt(1), later = appt(48)
        let upcoming = Appointment.upcoming([later, past, soon], now: now)
        XCTAssertEqual(upcoming.map(\.id), [soon.id, later.id], "future only, soonest first")
        XCTAssertFalse(upcoming.contains { $0.id == past.id }, "past excluded")
    }

    func testPastIsHistorySortedMostRecentFirst() {
        let old = appt(-72), recent = appt(-1), future = appt(5)
        let past = Appointment.past([old, future, recent], now: now)
        XCTAssertEqual(past.map(\.id), [recent.id, old.id], "past only, most recent first")
    }

    func testNextIsTheSoonestUpcoming() {
        let soon = appt(3), later = appt(30)
        XCTAssertEqual(Appointment.next([later, soon, appt(-4)], now: now)?.id, soon.id)
        XCTAssertNil(Appointment.next([appt(-1), appt(-10)], now: now), "no future → no next")
    }

    func testIsPastBoundary() {
        XCTAssertTrue(appt(-0.001).isPast(now: now))
        XCTAssertFalse(appt(0.001).isPast(now: now))
    }

    func testReminderFireDateHonoursLeadAndSkipsPast() {
        // 48h out, 1-day lead → fires 24h before start, which is 24h in the future.
        let fire = try? XCTUnwrap(appt(48, lead: 1440).reminderFireDate(now: now))
        XCTAssertEqual(fire, now.addingTimeInterval(24 * 3600))

        // 1h out, 1-day lead → fire time already passed → nil (can't schedule the past).
        XCTAssertNil(appt(1, lead: 1440).reminderFireDate(now: now), "lead window already elapsed")

        // Reminders off → nil regardless of timing.
        XCTAssertNil(appt(48, lead: nil).reminderFireDate(now: now))
    }

    func testSubtitleJoinsPresentFields() {
        XCTAssertEqual(appt(1, provider: "Dr. Smith", location: "City Clinic").subtitle, "Dr. Smith · City Clinic")
        XCTAssertEqual(appt(1, provider: "Dr. Smith").subtitle, "Dr. Smith")
        XCTAssertEqual(appt(1, provider: "  ", location: "Clinic").subtitle, "Clinic", "blank fields dropped")
        XCTAssertNil(appt(1).subtitle, "no provider/location → nil")
    }
}
