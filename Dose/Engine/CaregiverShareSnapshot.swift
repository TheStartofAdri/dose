import Foundation

/// SPIKE — Phase 0 (see `docs/caregiver-sharing-spike.md`). The minimized, **read-only** payload a
/// caregiver would see. Pure + `Codable`, so the data-shaping is proven and tested **entirely offline** —
/// nothing in this file sends data anywhere. Uploading it under a revocable token (Phase 1) reopens the
/// locked local-only decision and is intentionally NOT built here.
struct CaregiverShareSnapshot: Codable, Equatable {
    let generatedAt: Date
    /// A user-set nickname — never a real name by default. Data minimization.
    let patientLabel: String?
    let rangeDays: Int
    let overallAdherencePercent: Int?
    let medicines: [MedShare]
    let upcomingAppointments: [ApptShare]
    let metrics: [MetricShare]

    struct MedShare: Codable, Equatable {
        let name: String
        let adherencePercent: Int?
        let taken: Int
        let missed: Int
    }
    struct ApptShare: Codable, Equatable {
        let title: String
        let subtitle: String?   // provider · location
        let when: Date
    }
    struct MetricShare: Codable, Equatable {
        let name: String
        let unit: String?
        let latest: Double?     // manual entries only — HealthKit-sourced values are excluded
    }
}

/// Builds a `CaregiverShareSnapshot` by reusing the tested `ReportBuilder` for adherence and computing
/// upcoming appointments directly, while **excluding HealthKit-sourced metric values** (Apple's sharing
/// terms restrict re-sharing HealthKit data). Pure/offline by design — the network half (Phase 1) is out.
enum CaregiverShareBuilder {
    /// Bound the shared appointment list, mirroring the report.
    static let maxAppointments = 12

    /// One logged metric value plus its provenance — so the builder can drop HealthKit-sourced values.
    struct MetricEntryInput {
        let name: String
        let unit: String?
        let value: Double
        let loggedAt: Date
        let isHealthKit: Bool
    }

    static func build(
        medicines: [MedicineSnapshot],
        logs: [DoseLogSnapshot],
        appointments: [AppointmentSnapshot],
        metricEntries: [MetricEntryInput],
        patientLabel: String? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CaregiverShareSnapshot {
        // Adherence over the last 30 days — reuse the report engine so the caregiver's numbers match the app.
        let report = ReportBuilder.build(medicines: medicines, logs: logs, range: .last30,
                                         now: now, generatedAt: now, calendar: calendar)
        let meds = report.lines.map {
            CaregiverShareSnapshot.MedShare(name: $0.name, adherencePercent: $0.ratePercent,
                                            taken: $0.taken, missed: $0.missed)
        }

        // Upcoming appointments only (future), soonest first, bounded.
        let upcoming = appointments
            .filter { $0.startsAt >= now }
            .sorted { $0.startsAt < $1.startsAt }
            .prefix(maxAppointments)
            .map { CaregiverShareSnapshot.ApptShare(title: $0.title, subtitle: $0.subtitle, when: $0.startsAt) }

        // EXCLUDE HealthKit-sourced values, then take the latest manual value per metric name.
        let manual = metricEntries.filter { !$0.isHealthKit }
        let metrics = Dictionary(grouping: manual, by: \.name)
            .map { name, entries -> CaregiverShareSnapshot.MetricShare in
                let latest = entries.max { $0.loggedAt < $1.loggedAt }
                return CaregiverShareSnapshot.MetricShare(name: name, unit: latest?.unit, latest: latest?.value)
            }
            .sorted { $0.name < $1.name }

        return CaregiverShareSnapshot(
            generatedAt: now, patientLabel: patientLabel, rangeDays: report.summary.periodDays,
            overallAdherencePercent: report.summary.overallRatePercent,
            medicines: meds, upcomingAppointments: Array(upcoming), metrics: metrics)
    }
}
