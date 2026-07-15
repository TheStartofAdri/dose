import XCTest
import SwiftData
@testable import Dose

/// Input invariants at the write boundary: a title is required, and a reminder lead can't be negative
/// (which would fire a reminder AFTER the appointment).
@MainActor
final class AppointmentWriterTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = DoseStore.currentSchema
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    func testCreateRejectsBlankTitleAndPersistsNothing() throws {
        let context = try makeContext()
        XCTAssertThrowsError(try AppointmentWriter.create(
            title: "   ", providerName: nil, location: nil, startsAt: .now,
            durationMinutes: nil, notes: nil, reminderLeadMinutes: 1440, into: context)) { error in
            XCTAssertEqual(error as? AppointmentWriterError, .emptyTitle)
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<Appointment>()).count, 0, "nothing persisted")
    }

    func testCreateClampsNegativeLeadToZero() throws {
        let context = try makeContext()
        let appt = try AppointmentWriter.create(
            title: "Visit", providerName: nil, location: nil,
            startsAt: Date(timeIntervalSince1970: 1_900_000_000),
            durationMinutes: nil, notes: nil, reminderLeadMinutes: -30, into: context)
        XCTAssertEqual(appt.reminderLeadMinutes, 0, "negative lead clamped to 0 (at the time)")
    }

    func testUpdateRejectsBlankTitle() throws {
        let context = try makeContext()
        let appt = try AppointmentWriter.create(
            title: "Visit", providerName: nil, location: nil, startsAt: .now,
            durationMinutes: nil, notes: nil, reminderLeadMinutes: nil, into: context)
        XCTAssertThrowsError(try AppointmentWriter.update(
            appt, title: "\n ", providerName: nil, location: nil, startsAt: .now,
            durationMinutes: nil, notes: nil, reminderLeadMinutes: nil, into: context)) { error in
            XCTAssertEqual(error as? AppointmentWriterError, .emptyTitle)
        }
    }
}
