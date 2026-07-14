import Foundation

/// Builds `ReportData` purely from snapshots, reusing `AdherenceCalculator` so the report's numbers
/// match the rest of the app exactly (Skip neutral; pre-`createdAt` and post-`endDate` days excluded;
/// past-due untaken = missed). No PDF/UIKit here.
/// A tracked metric's chronological values within the report range — the pure input the builder needs
/// (the view maps `TrackedMetric`/`MetricEntry` to this so the builder stays snapshot-only).
struct MetricReportInput {
    let name: String
    let unit: String?
    /// Chronological values (oldest → newest) so `latest` is `values.last`.
    let values: [Double]
}

enum ReportBuilder {
    /// The most upcoming appointments any single report lists — enough for a care schedule, bounded so a
    /// user with many future visits doesn't produce an unwieldy doctor handout.
    static let maxAppointments = 12

    static func build(
        medicines: [MedicineSnapshot],
        logs: [DoseLogSnapshot],
        range: ReportRange,
        metricInputs: [MetricReportInput] = [],
        appointments: [AppointmentSnapshot] = [],
        now: Date = .now,
        generatedAt: Date = .now,
        calendar: Calendar = .current
    ) -> ReportData {
        let (from, to) = range.resolved(now: now, calendar: calendar)
        let lines = medicines.map { med -> ReportData.MedLine in
            let series = AdherenceCalculator.days(medicines: [med], logs: logs, from: from, to: to, now: now, calendar: calendar)
            let rate = AdherenceCalculator.rate(series)
            return ReportData.MedLine(
                id: med.id,
                name: med.name,
                dosage: med.dosage,
                ratePercent: rate.map { Int(($0 * 100).rounded()) },
                taken: series.reduce(0) { $0 + $1.taken },
                skipped: series.reduce(0) { $0 + $1.skipped },
                missed: series.reduce(0) { $0 + $1.missed },
                days: series
            )
        }

        // Aggregate totals (the same per-med series summed → the report's overall % matches the app's).
        let taken = lines.reduce(0) { $0 + $1.taken }
        let skipped = lines.reduce(0) { $0 + $1.skipped }
        let missed = lines.reduce(0) { $0 + $1.missed }
        let counted = taken + missed
        let periodDays = (calendar.dateComponents([.day], from: calendar.startOfDay(for: from),
                                                  to: calendar.startOfDay(for: to)).day ?? 0) + 1
        let summary = ReportData.Summary(
            periodDays: periodDays,
            scheduled: taken + skipped + missed,
            taken: taken, skipped: skipped, missed: missed,
            overallRatePercent: counted > 0 ? Int((Double(taken) / Double(counted) * 100).rounded()) : nil
        )

        let metrics = metricInputs.map { input -> ReportData.MetricSummary in
            let v = input.values
            return ReportData.MetricSummary(
                id: UUID(), name: input.name, unit: input.unit, count: v.count,
                latest: v.last, average: v.isEmpty ? nil : v.reduce(0, +) / Double(v.count),
                minimum: v.min(), maximum: v.max())
        }

        // Upcoming appointments only (future visits) — independent of the past adherence range —
        // soonest first, bounded so the handout stays reasonable.
        let upcomingAppointments = appointments
            .filter { $0.startsAt >= now }
            .sorted { $0.startsAt < $1.startsAt }
            .prefix(maxAppointments)
            .map { ReportData.AppointmentLine(id: $0.id, title: $0.title, subtitle: $0.subtitle, when: $0.startsAt) }

        return ReportData(rangeStart: from, rangeEnd: to, generatedAt: generatedAt,
                          lines: lines, summary: summary, metrics: metrics, appointments: upcomingAppointments)
    }
}
