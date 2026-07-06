import Foundation

/// Builds `ReportData` purely from snapshots, reusing `AdherenceCalculator` so the report's numbers
/// match the rest of the app exactly (Skip neutral; pre-`createdAt` and post-`endDate` days excluded;
/// past-due untaken = missed). No PDF/UIKit here.
enum ReportBuilder {
    static func build(
        medicines: [MedicineSnapshot],
        logs: [DoseLogSnapshot],
        range: ReportRange,
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

        return ReportData(rangeStart: from, rangeEnd: to, generatedAt: generatedAt, lines: lines, summary: summary)
    }
}
