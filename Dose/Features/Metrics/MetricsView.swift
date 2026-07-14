import SwiftUI
import SwiftData

/// The capture surface for symptoms & vitals — reached from Today. Lists what the user tracks with its
/// latest reading and a one-tap log; a `+` adds a new metric. Trends live on the Insights tab.
struct MetricsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrackedMetric.sortOrder) private var metrics: [TrackedMetric]
    @State private var showAdd = false
    @State private var logging: TrackedMetric?

    private var active: [TrackedMetric] { TrackedMetric.active(metrics) }

    var body: some View {
        NavigationStack {
            Group {
                if active.isEmpty {
                    VStack {
                        Spacer()
                        DoseEmptyState(icon: "heart.text.square",
                                       title: "Track how you feel",
                                       message: "Log symptoms and vitals in seconds — pain, mood, sleep, weight, and more.") {
                            Button { showAdd = true } label: { Label("Track something", systemImage: "plus") }
                                .buttonStyle(.borderedProminent)
                        }
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(active) { metric in
                            Button { logging = metric } label: { row(metric) }
                                .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Track")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Track something")
                }
            }
            .sheet(isPresented: $showAdd) { AddMetricSheet() }
            .sheet(item: $logging) { LogMetricSheet(metric: $0) }
        }
    }

    private func row(_ metric: TrackedMetric) -> some View {
        HStack(spacing: 12) {
            MedicineIconBadge(iconName: metric.iconName, colorHex: metric.colorHex, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(metric.name).font(.subheadline.weight(.medium))
                if let last = metric.latestEntry {
                    Text("\(last.displayValue) · \(last.loggedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No entries yet — tap to log").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if metric.hasEntryToday() {
                Label("Logged", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(DoseColors.taken)
                    .accessibilityLabel("Logged today")
            } else {
                Text("Log").font(.caption.weight(.semibold)).foregroundStyle(DoseColors.accent)
            }
        }
        .contentShape(Rectangle())
    }

    /// Deleting a metric removes it and (cascade) its entries.
    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(active[index]) }
        try? context.save()
    }
}
