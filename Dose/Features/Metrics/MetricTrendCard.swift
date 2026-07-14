import SwiftUI
import Charts

/// A compact trend for one tracked metric on the Insights tab — the recent entries as a line, with the
/// latest reading called out. Purely descriptive (an observation, never a diagnosis).
struct MetricTrendCard: View {
    let metric: TrackedMetric
    /// Recent entries in chronological order (oldest → newest), already filtered to chartable values.
    let entries: [MetricEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                MedicineIconBadge(iconName: metric.iconName, colorHex: metric.colorHex, size: 26)
                Text(metric.name).font(.headline)
                Spacer(minLength: 0)
                if let last = entries.last {
                    Text(last.displayValue)
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if entries.count >= 2 {
                Chart(entries, id: \.id) { entry in
                    if let y = entry.chartValue {
                        LineMark(x: .value("When", entry.loggedAt), y: .value("Value", y))
                            .foregroundStyle(MedAppearance.color(metric.colorHex))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("When", entry.loggedAt), y: .value("Value", y))
                            .foregroundStyle(MedAppearance.color(metric.colorHex))
                            .symbolSize(18)
                    }
                }
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                        AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 110)
            } else {
                Text("Log a few more to see a trend.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .doseCardStyle()
    }

    /// A consistent `Double` Y-domain: fixed 0–10 for severity, else the data range with light padding.
    private var yDomain: ClosedRange<Double> {
        if metric.valueKind == .severity { return 0...10 }
        let ys = entries.compactMap(\.chartValue)
        guard let lo = ys.min(), let hi = ys.max() else { return 0...1 }
        if lo == hi { return (lo - 1)...(hi + 1) }
        let pad = (hi - lo) * 0.1
        return (lo - pad)...(hi + pad)
    }
}
