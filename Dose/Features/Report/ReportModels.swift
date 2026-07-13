import Foundation

/// The date window a report covers.
enum ReportRange: Equatable {
    case last7
    case last30
    case custom(from: Date, to: Date)

    /// Resolve to a concrete `[from, to]`. `to` is the real `now` for the presets so "last 7 days"
    /// includes today without counting today's not-yet-due doses as missed.
    func resolved(now: Date = .now, calendar: Calendar = .current) -> (from: Date, to: Date) {
        switch self {
        case .last7:
            return (calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now, now)
        case .last30:
            return (calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now, now)
        case .custom(let from, let to):
            // Order the endpoints, and never let `to` run past `now` — a future end would inflate the
            // "days tracked" header with empty not-yet-happened days (B6).
            let lo = min(from, to)
            let hi = min(max(from, to), now)
            return (lo, hi)
        }
    }
}

/// A finished, value-type report ready to render. Built purely from snapshots so it's testable
/// without any PDF/UIKit involvement.
struct ReportData {
    let rangeStart: Date
    let rangeEnd: Date
    let generatedAt: Date
    let lines: [MedLine]
    let summary: Summary

    /// At-a-glance totals across all selected medicines, so a first-time reader can tell how much
    /// was tracked. Aggregated from the same per-med `AdherenceCalculator` series → matches the app.
    struct Summary {
        let periodDays: Int
        let scheduled: Int       // taken + skipped + missed across all selected meds
        let taken: Int
        let skipped: Int
        let missed: Int
        let overallRatePercent: Int?   // taken ÷ (taken + missed); nil when nothing counted
    }

    /// One medicine's adherence over the range.
    struct MedLine: Identifiable {
        let id: UUID
        let name: String
        let dosage: String?
        /// taken ÷ (taken + missed), as a whole percent; `nil` when nothing counted in the range.
        let ratePercent: Int?
        let taken: Int
        let skipped: Int
        let missed: Int
        /// Per-day series (oldest → newest) for the day-by-day strip.
        let days: [DayAdherence]

        /// Whether anything was scheduled in range. `false` meds are omitted from the report body.
        var hasScheduledDoses: Bool { taken + skipped + missed > 0 }
    }
}
