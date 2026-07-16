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
                let items = active   // one snapshot for both the list and its swipe-delete (see `delete`)
                if items.isEmpty {
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
                        ForEach(items) { metric in
                            Button { logging = metric } label: { row(metric) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { offsets in delete(items, offsets) }
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
                    .font(.subheadline)          // cap it — an un-fonted iconOnly Label renders body-size,
                    .foregroundStyle(DoseColors.taken)   // so the row's right edge jumped vs. the "Log" caption
                    .accessibilityLabel("Logged today")
            } else {
                Text("Log").font(.caption.weight(.semibold)).foregroundStyle(DoseColors.accent)
            }
        }
        .contentShape(Rectangle())
    }

    /// Deleting a metric removes it and (cascade) its entries. Takes the SAME array the `ForEach` rendered
    /// (not the `active` computed var, which re-filters on each access) so the swipe offsets can't index a
    /// shifted/short array if the @Query refires mid-delete — matching NotesView/AppointmentsView.
    private func delete(_ items: [TrackedMetric], _ offsets: IndexSet) {
        for index in offsets { context.delete(items[index]) }
        try? context.save()
    }
}
