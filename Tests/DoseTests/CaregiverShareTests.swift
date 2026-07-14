import XCTest
@testable import Dose

/// SPIKE — Phase 0. The caregiver-share payload is shaped correctly and produced **entirely offline**.
/// The key property under test is the privacy rule: HealthKit-sourced metric values never enter the
/// share. Nothing here touches a network — Phase 1 (uploading under a revocable token) is out of scope.
final class CaregiverShareTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 8) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }
    private func med(_ name: String, _ id: UUID) -> MedicineSnapshot {
        MedicineSnapshot(id: id, name: name, dosage: "5 mg",
                         rules: [DoseSlotRule(hour: 8, minute: 0)], createdAt: at(2026, 6, 1))
    }

    func testAdherenceAndMedsDerivedFromReport() {
        let now = at(2026, 6, 16, 23)
        let id = UUID()
        let logs = [DoseLogSnapshot(medicineID: id, scheduledFor: at(2026, 6, 14), action: .taken, actionedAt: at(2026, 6, 14)),
                    DoseLogSnapshot(medicineID: id, scheduledFor: at(2026, 6, 15), action: .taken, actionedAt: at(2026, 6, 15))]
        let snap = CaregiverShareBuilder.build(medicines: [med("Aspirin", id)], logs: logs,
                                               appointments: [], metricEntries: [], now: now, calendar: cal)
        XCTAssertEqual(snap.medicines.first?.name, "Aspirin")
        XCTAssertEqual(snap.medicines.first?.taken, 2)
        XCTAssertNotNil(snap.overallAdherencePercent, "overall adherence is derived from the report engine")
        XCTAssertEqual(snap.rangeDays, 30)
    }

    func testUpcomingAppointmentsOnlyFutureSoonestFirst() {
        let now = at(2026, 6, 16, 12)
        func appt(_ d: Int, _ t: String) -> AppointmentSnapshot {
            AppointmentSnapshot(id: UUID(), title: t, subtitle: nil, startsAt: at(2026, 6, d, 10), reminderLeadMinutes: 1440)
        }
        let snap = CaregiverShareBuilder.build(medicines: [], logs: [],
            appointments: [appt(20, "B"), appt(10, "past"), appt(18, "A")], metricEntries: [], now: now, calendar: cal)
        XCTAssertEqual(snap.upcomingAppointments.map(\.title), ["A", "B"], "future only, soonest first")
    }

    /// The privacy rule: HealthKit-sourced values are excluded; manual ones are kept (latest wins).
    func testHealthKitSourcedMetricsExcluded() {
        let now = at(2026, 6, 16, 12)
        let entries = [
            CaregiverShareBuilder.MetricEntryInput(name: "Weight", unit: "kg", value: 70, loggedAt: at(2026, 6, 10), isHealthKit: false),
            CaregiverShareBuilder.MetricEntryInput(name: "Weight", unit: "kg", value: 71, loggedAt: at(2026, 6, 15), isHealthKit: false),
            CaregiverShareBuilder.MetricEntryInput(name: "Heart rate", unit: "bpm", value: 62, loggedAt: at(2026, 6, 15), isHealthKit: true),
        ]
        let snap = CaregiverShareBuilder.build(medicines: [], logs: [], appointments: [], metricEntries: entries, now: now, calendar: cal)
        XCTAssertEqual(snap.metrics.map(\.name), ["Weight"], "HealthKit-sourced 'Heart rate' is excluded")
        XCTAssertEqual(snap.metrics.first?.latest, 71, "latest manual value")
    }

    func testPayloadIsCodableRoundTrip() throws {
        let now = at(2026, 6, 16, 12)
        let snap = CaregiverShareBuilder.build(medicines: [], logs: [],
            appointments: [AppointmentSnapshot(id: UUID(), title: "Visit", subtitle: "Dr. X",
                                               startsAt: at(2026, 7, 1, 9), reminderLeadMinutes: 60)],
            metricEntries: [], patientLabel: "Mum", now: now, calendar: cal)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let round = try dec.decode(CaregiverShareSnapshot.self, from: enc.encode(snap))
        XCTAssertEqual(round, snap, "the share payload serializes losslessly — ready to upload in Phase 1")
    }
}
