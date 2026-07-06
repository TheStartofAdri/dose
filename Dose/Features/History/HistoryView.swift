import SwiftUI
import SwiftData
import Charts

/// Behavioural history (free): a streak hero, two clearly-labelled adherence rates, and a 14-day
/// adherence chart. Everything is derived from `DoseLog` via `AdherenceCalculator` — the header
/// percentages and the chart read the **same** corrected per-day series, so they can never disagree.
struct HistoryView: View {
    @Query(sort: \Medicine.name) private var medicines: [Medicine]
    @Query(sort: \DoseLog.scheduledFor) private var logs: [DoseLog]

    @State private var showReport = false
    @State private var showPaywall = false
    @ObservedObject private var subscription = SubscriptionStore.shared   // re-render on entitlement change

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 300)) { timeline in
                content(now: timeline.date)
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Premium export, routed through the single entitlement seam. Non-subscribers get the
                    // unlock paywall (history itself stays free).
                    Button {
                        if Entitlements.isPremium { showReport = true } else { showPaywall = true }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export report")
                }
            }
            .sheet(isPresented: $showReport) {
                NavigationStack { ReportOptionsView(preselected: nil) }
            }
            .sheet(isPresented: $showPaywall) { PaywallView(context: .unlock(.reportExport)) }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let meds = Medicine.activeConfirmed(medicines).map { $0.snapshot() }
        let logSnaps = logs.map { $0.snapshot() }

        // The single corrected source. `series` is oldest→newest; the header and the chart both slice
        // from it, so a polished chart can never drift from the headline numbers.
        let series = AdherenceCalculator.days(medicines: meds, logs: logSnaps, now: now, days: 30)
        let last14 = Array(series.suffix(14))
        let last7 = Array(series.suffix(7))
        let streak = StreakCalculator.currentStreak(medicines: meds, logs: logSnaps, now: now)
        let rate7 = AdherenceCalculator.rate(last7)
        let rate30 = AdherenceCalculator.rate(series)

        if meds.isEmpty {
            ContentUnavailableView("No history yet", systemImage: "chart.bar.xaxis",
                                   description: Text("Adherence and streaks appear once you're tracking medicines."))
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    StreakBanner(streak: streak)
                    AdherenceStatRow(rate7: rate7, rate30: rate30)
                    AdherenceChartCard(days: last14)
                    MissedThisWeekCard(days: last7)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Streak hero (the encouraging element)

private struct StreakBanner: View {
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
                Text(streak == 1 ? "day streak" : "day streak")
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
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private var encouragement: String {
        switch streak {
        case 0:  "Take a dose to start your streak"
        case 1:  "Nice start — keep it going"
        case 2...6: "You're building a habit"
        default: "Great consistency 🎉"
        }
    }
}

// MARK: - Adherence rates (clearly labelled, same source as the chart)

private struct AdherenceStatRow: View {
    let rate7: Double?
    let rate30: Double?

    var body: some View {
        HStack(spacing: 12) {
            RateTile(title: "7-day", caption: "adherence", rate: rate7)
            RateTile(title: "30-day", caption: "adherence", rate: rate30)
        }
    }
}

private struct RateTile: View {
    let title: String
    let caption: String
    let rate: Double?      // nil = no scheduled doses in the window → neutral, not 0%/100%

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(display)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(rate == nil ? .secondary : color)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .doseCard()
    }

    private var display: String {
        guard let rate else { return "—" }
        return "\(Int((rate * 100).rounded()))%"
    }

    private var color: Color {
        guard let rate else { return .secondary }
        if rate >= 0.8 { return .green }
        if rate >= 0.5 { return .orange }
        return .red
    }
}

// MARK: - Adherence timeline chart (shared by History and Medicine detail)

/// A discrete per-day bar chart across a FIXED date axis, so one day of data reads as a single
/// narrow bar on a real timeline — not a slab stretched across the width. Empty days render as a
/// small neutral baseline tick rather than vanishing. Taken (green) / Skipped (grey, neutral) /
/// Missed (red), matching the adherence math exactly.
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
                "Taken": Color.green,
                // A solid, clearly-visible gray — distinct from the faint neutral tick used for
                // empty days. Skips are shown but never scored (neutral for the % and streak).
                "Skipped": Color(.systemGray),
                "Missed": Color.red,
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
        .doseCard()
    }

    /// Lock the x-axis to the full window (padded half a day each side) so a single day's bar
    /// occupies one slot instead of stretching across the plot.
    private var domain: ClosedRange<Date> {
        let start = days.first?.date ?? .now
        let end = days.last?.date ?? .now
        return start.addingTimeInterval(-43_200) ... end.addingTimeInterval(43_200)
    }
}

private struct DayBar: Identifiable {
    let date: Date
    let status: String
    let count: Int
    var id: String { "\(date.timeIntervalSince1970)-\(status)" }
}

// MARK: - Missed-this-week callout

private struct MissedThisWeekCard: View {
    let days: [DayAdherence]

    var body: some View {
        let missed = days.reduce(0) { $0 + $1.missed }
        return HStack(spacing: 12) {
            Image(systemName: missed == 0 ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(missed == 0 ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(missed == 0 ? "Nothing missed this week" : "\(missed) missed this week")
                    .font(.subheadline.weight(.semibold))
                Text(missed == 0 ? "Every past-due dose was taken or skipped." : "Past-due doses with no action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .doseCard()
    }
}
