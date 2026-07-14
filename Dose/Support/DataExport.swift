import Foundation

/// A plain-value JSON export of everything Dose stores, for the user's "export my data" right (a trust +
/// data-portability expectation for health apps). Nothing leaves the device except by the user's explicit
/// share of the produced file. Photo bytes are summarised as a count, not dumped, to keep the file small.
enum DataExport {
    struct Payload: Codable, Equatable {
        var exportedAt: Date
        var medicines: [Med]
        var doseLogs: [Log]
        var notes: [NoteDTO]
        var metrics: [MetricDTO] = []
        var appointments: [AppointmentDTO] = []
    }
    struct AppointmentDTO: Codable, Equatable {
        var id: UUID; var title: String; var providerName: String?; var location: String?
        var startsAt: Date; var durationMinutes: Int?; var notes: String?
        var reminderLeadMinutes: Int?; var createdAt: Date
    }
    struct MetricDTO: Codable, Equatable {
        var id: UUID; var name: String; var kind: String; var valueKind: String; var unit: String?
        var isActive: Bool; var entries: [MetricEntryDTO]
    }
    struct MetricEntryDTO: Codable, Equatable {
        var id: UUID; var value: Double?; var severity: Int?; var note: String?
        var loggedAt: Date; var source: String
    }
    struct Med: Codable, Equatable {
        var id: UUID; var name: String; var dosage: String?; var form: String?; var quantity: String?
        var instructions: String?; var isActive: Bool; var createdAt: Date; var endDate: Date?
        var leadTimeMinutes: Int?; var unitsAtRefill: Int?; var refillDate: Date?; var unitsPerDose: Int
        var refillThresholdDays: Int?; var schedule: [Sched]
    }
    struct Sched: Codable, Equatable {
        var hour: Int; var minute: Int; var weekdays: [Int]; var intervalDays: Int
        var anchorDate: Date?; var daysOfMonth: [Int]
    }
    struct Log: Codable, Equatable {
        var medicineID: UUID; var medicineName: String; var dosage: String?; var scheduledFor: Date
        var action: String; var actionedAt: Date; var snoozeMinutes: Int?
    }
    struct NoteDTO: Codable, Equatable {
        var id: UUID; var text: String; var createdAt: Date; var tags: [String]
        var medicineID: UUID?; var photoCount: Int
    }

    @MainActor
    static func payload(medicines: [Medicine], logs: [DoseLog], notes: [Note],
                        metrics: [TrackedMetric] = [], appointments: [Appointment] = [],
                        now: Date = .now) -> Payload {
        Payload(
            exportedAt: now,
            medicines: medicines.map { m in
                Med(id: m.id, name: m.name, dosage: m.dosage, form: m.form, quantity: m.quantity,
                    instructions: m.instructions, isActive: m.isActive, createdAt: m.createdAt, endDate: m.endDate,
                    leadTimeMinutes: m.leadTimeMinutes, unitsAtRefill: m.unitsAtRefill, refillDate: m.refillDate,
                    unitsPerDose: m.unitsPerDose, refillThresholdDays: m.refillThresholdDays,
                    schedule: m.doseTimes.map {
                        Sched(hour: $0.hour, minute: $0.minute, weekdays: $0.weekdays,
                              intervalDays: $0.intervalDays, anchorDate: $0.anchorDate, daysOfMonth: $0.daysOfMonth)
                    })
            },
            doseLogs: logs.map {
                Log(medicineID: $0.medicineID, medicineName: $0.medicineName, dosage: $0.dosage,
                    scheduledFor: $0.scheduledFor, action: $0.action.rawValue, actionedAt: $0.actionedAt,
                    snoozeMinutes: $0.snoozeMinutes)
            },
            notes: notes.map {
                NoteDTO(id: $0.id, text: $0.text, createdAt: $0.createdAt, tags: $0.tags,
                        medicineID: $0.medicineID, photoCount: $0.photos.count)
            },
            metrics: metrics.map { m in
                MetricDTO(id: m.id, name: m.name, kind: m.kindRaw, valueKind: m.valueKindRaw, unit: m.unit,
                          isActive: m.isActive, entries: m.entries.map {
                    MetricEntryDTO(id: $0.id, value: $0.value, severity: $0.severity, note: $0.note,
                                   loggedAt: $0.loggedAt, source: $0.sourceRaw)
                })
            },
            appointments: appointments.map { a in
                AppointmentDTO(id: a.id, title: a.title, providerName: a.providerName, location: a.location,
                               startsAt: a.startsAt, durationMinutes: a.durationMinutes, notes: a.notes,
                               reminderLeadMinutes: a.reminderLeadMinutes, createdAt: a.createdAt)
            }
        )
    }

    static func encode(_ payload: Payload) throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(payload)
    }

    /// Writes the export to a temp file and returns its URL (for the share sheet). Name includes the date.
    @MainActor
    static func writeTempFile(medicines: [Medicine], logs: [DoseLog], notes: [Note],
                              metrics: [TrackedMetric] = [], appointments: [Appointment] = [],
                              now: Date = .now) throws -> URL {
        let data = try encode(payload(medicines: medicines, logs: logs, notes: notes, metrics: metrics,
                                      appointments: appointments, now: now))
        let stamp = ISO8601DateFormatter().string(from: now).prefix(10)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Dose-export-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }
}
