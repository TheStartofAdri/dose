import XCTest
import SwiftData
@testable import Dose

/// Phase 1 (data rights): the JSON export captures the full local dataset and round-trips losslessly.
@MainActor
final class DataExportTests: XCTestCase {
    func testPayloadCapturesModelsAndRoundTripsThroughJSON() throws {
        let schema = DoseStore.currentSchema
        let container = try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let ctx = container.mainContext
        // Whole-second dates so the (intentionally second-granular) ISO-8601 export round-trips exactly.
        let t = Date(timeIntervalSince1970: 1_780_000_000)
        let med = Medicine(name: "Aspirin", dosage: "100 mg", trustState: .confirmed, createdAt: t,
                           unitsAtRefill: 30, unitsPerDose: 1, refillThresholdDays: 7)
        med.doseTimes = [DoseTime(hour: 8, minute: 0)]
        ctx.insert(med)
        let log = DoseLog(medicineID: med.id, medicineName: "Aspirin", scheduledFor: t, action: .taken, actionedAt: t)
        ctx.insert(log)
        let note = Note(text: "felt fine", createdAt: t, tags: [NoteTag.general.rawValue])
        ctx.insert(note)
        let metric = TrackedMetric(name: "Pain", kind: .symptom, valueKind: .severity, createdAt: t)
        ctx.insert(metric)
        ctx.insert(MetricEntry(severity: 6, loggedAt: t, metric: metric))
        let appt = Appointment(title: "Cardiology follow-up", providerName: "Dr. Smith", location: "City Clinic",
                               startsAt: t, durationMinutes: 30, notes: "bring meds list",
                               reminderLeadMinutes: 1440, createdAt: t)
        ctx.insert(appt)
        try ctx.save()

        let payload = DataExport.payload(medicines: [med], logs: [log], notes: [note], metrics: [metric],
                                         appointments: [appt],
                                         now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(payload.medicines.count, 1)
        XCTAssertEqual(payload.metrics.count, 1)
        XCTAssertEqual(payload.metrics.first?.entries.first?.severity, 6)
        XCTAssertEqual(payload.medicines.first?.unitsAtRefill, 30)
        XCTAssertEqual(payload.medicines.first?.refillThresholdDays, 7)
        XCTAssertEqual(payload.medicines.first?.schedule.first?.hour, 8)
        XCTAssertEqual(payload.doseLogs.first?.action, "taken")
        XCTAssertEqual(payload.notes.first?.text, "felt fine")
        XCTAssertEqual(payload.appointments.count, 1)
        XCTAssertEqual(payload.appointments.first?.title, "Cardiology follow-up")
        XCTAssertEqual(payload.appointments.first?.providerName, "Dr. Smith")
        XCTAssertEqual(payload.appointments.first?.reminderLeadMinutes, 1440)

        let data = try DataExport.encode(payload)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try dec.decode(DataExport.Payload.self, from: data), payload,
                       "the export round-trips losslessly through JSON")
    }
}
