import SwiftUI
import Charts

// Shared adherence visuals used by the Week tab and the Medicine detail screen (and formerly the
// History dashboard, which is now an event log). One definition each so a status/colour tweak lands
// everywhere at once; all colours come from the single `DoseColors` palette.

/// A discrete per-day bar chart across a FIXED date axis, so one day of data reads as a single narrow
/// bar on a real timeline — not a slab stretched across the width. Empty days render as a small neutral
/// baseline tick rather than vanishing. Taken (green) / Skipped (neutral) / Missed (red), matching the
/// adherence math exactly.
struct AdherenceChartCard: View {
    let days: [DayAdherence]
    var title: String = "Last 14 days"

    private var bars: [DayBar] {
        days.flatMap { day -> [DayBar] in
            var out: [DayBar] = []
            if day.taken > 0 { out.append(DayBar(date: day.date, status: "Taken", count: day.taken)) }
            if day.skipped > 0 { out.append(DayBar(date: day.date, status: "Skipped", count: day.skipped)) }
            if day.missed > 0 { out.append(DayBar(date: day.date, status: "Missed", count: day.missed)) }
            return out
        }
    }
    private var emptyDays: [Date] {
        days.filter { $0.taken == 0 && $0.skipped == 0 && $0.missed == 0 }.map(\.date)
    }
    private var maxCount: Int { max(1, days.map { $0.taken + $0.skipped + $0.missed }.max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("doses taken vs scheduled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Chart {
                // Neutral baseline tick for empty days, so the axis always reads as a timeline.
                ForEach(emptyDays, id: \.self) { date in
                    PointMark(x: .value("Day", date, unit: .day), y: .value("Doses", 0))
                        .symbolSize(20)
                        .foregroundStyle(Color.secondary.opacity(0.25))
                }
                // Status bars (stacked taken/skipped/missed) for days with data.
                ForEach(bars) { bar in
                    BarMark(
                        x: .value("Day", bar.date, unit: .day),
                        y: .value("Doses", bar.count),
                        width: .fixed(10)
                    )
                    .foregroundStyle(by: .value("Status", bar.status))
                    .cornerRadius(3)
                }
            }
            .chartForegroundStyleScale([
                "Taken": DoseColors.taken,
                // A solid, clearly-visible gray — distinct from the faint neutral tick used for
                // empty days. Skips are shown but never scored (neutral for the % and streak).
                "Skipped": DoseColors.neutralSolid,
                "Missed": DoseColors.missed,
            ])
            .chartXScale(domain: domain)
            .chartYScale(domain: 0...Double(maxCount))
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(0...maxCount).map(Double.init)) {
                    AxisGridLine(); AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartLegend(position: .bottom, spacing: 12)
            .frame(height: 200)
        }
        .doseCardStyle()
    }

    /// Lock the x-axis to the full window (padded half a day each side) so a single day's bar occupies
    /// one slot instead of stretching across the plot.
    private var domain: ClosedRange<Date> {
        let start = days.first?.date ?? .now
        let end = days.last?.date ?? .now
        return start.addingTimeInterval(-43_200) ... end.addingTimeInterval(43_200)
    }
}

struct DayBar: Identifiable {
    let date: Date
    let status: String
    let count: Int
    var id: String { "\(date.timeIntervalSince1970)-\(status)" }
}

/// The encouraging streak hero — a warm gradient card with the current day-streak and a message.
struct StreakBanner: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(streak)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("day streak")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            Text(encouragement)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.95))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 130, alignment: .trailing)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.orange, Color(red: 0.95, green: 0.45, blue: 0.2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: DoseRadius.card, style: .continuous)
        )
    }

    private var encouragement: String {
        switch streak {
        case 0:  "Take a dose to start your streak"
        case 1:  "Nice start — keep it going"
        case 2...6: "You're building a habit"
        default: "Great consistency"
        }
    }
}
