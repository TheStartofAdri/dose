import SwiftUI
import SwiftData

/// History (free): a chronological EVENT LOG of what actually happened — every taken / skipped /
/// snoozed action (from `DoseLog`) interleaved with derived misses, grouped by day and filterable.
/// The analytics that used to live here (streak, rates, chart) now live on the Week tab.
///
/// The derived "Missed" events come from `AdherenceCalculator.missedEvents`, the SAME source as Week's
/// missed count — so the Missed filter here and "missed this week" there can never disagree.
struct HistoryView: View {
    @Query(sort: \Medicine.name) private var medicines: [Medicine]
    @Query(sort: \DoseLog.scheduledFor, order: .reverse) private var logs: [DoseLog]

    @State private var showReport = false
    @State private var showPaywall = false
    @State private var filter: EventFilter = .all
    @State private var search = ""
    @ObservedObject private var subscription = SubscriptionStore.shared   // re-render on entitlement change

    /// Rolling window for the log — recent enough to stay fast; the full record is in the PDF export.
    private let windowDays = 30

    enum EventFilter: String, CaseIterable, Identifiable {
        case all = "All", taken = "Taken", skipped = "Skipped", snoozed = "Snoozed", missed = "Missed"
        var id: String { rawValue }
        var status: DoseStatus? {
            switch self {
            case .all: nil
            case .taken: .taken
            case .skipped: .skipped
            case .snoozed: .snoozed
            case .missed: .missed
            }
        }
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 300)) { timeline in
                content(now: timeline.date)
            }
            .navigationTitle("History")
            .searchable(text: $search, prompt: "Search medicine")
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
        let grouped = groupedEvents(now: now)

        // "No history yet" only when there's genuinely nothing to show. DoseLog is intentionally never
        // cascade-deleted (the delete dialog promises "history is kept"), so retained logs must still
        // appear after the last Medicine is deleted — gate on logs too, not medicines alone (A4).
        if medicines.isEmpty && logs.isEmpty {
            VStack {
                Spacer()
                DoseEmptyState(icon: "clock.arrow.circlepath",
                               title: "No history yet",
                               message: "Your taken, skipped, and missed doses will appear here.")
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
                filterChips
                if grouped.isEmpty {
                    Spacer()
                    DoseEmptyState(icon: "line.3.horizontal.decrease.circle",
                                   title: "Nothing to show",
                                   message: emptyMessage)
                    Spacer()
                } else {
                    List {
                        ForEach(grouped, id: \.day) { group in
                            Section(dayLabel(group.day, now: now)) {
                                ForEach(group.events) { event in
                                    HistoryEventRow(event: event)
                                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(DoseColors.groupedBackground)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DoseSpacing.sm) {
                ForEach(EventFilter.allCases) { f in
                    FilterChip(title: f.rawValue, isSelected: filter == f) { filter = f }
                }
            }
            .padding(.horizontal, DoseSpacing.lg)
            .padding(.vertical, DoseSpacing.sm)
        }
    }

    private var emptyMessage: String {
        let scope = filter == .all ? "" : " \(filter.rawValue.lowercased())"
        return search.isEmpty
            ? "No\(scope) doses in the last \(windowDays) days."
            : "No\(scope) doses match “\(search)”."
    }

    // MARK: - Event assembly

    private struct DayGroup { let day: Date; let events: [HistoryEvent] }

    private func groupedEvents(now: Date) -> [DayGroup] {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -(windowDays - 1), to: cal.startOfDay(for: now)) ?? now
        let meds = Medicine.activeConfirmed(medicines).map { $0.snapshot() }
        let logSnaps = logs.map { $0.snapshot() }

        var events: [HistoryEvent] = []
        // Real actions: one row per log (a take-then-skip shows both — honest action history).
        for log in logs where log.scheduledFor >= from {
            guard let status = status(for: log.action) else { continue }
            events.append(HistoryEvent(id: "log-\(log.id.uuidString)", medicineID: log.medicineID,
                                       medicineName: log.medicineName, dosage: log.dosage,
                                       scheduledFor: log.scheduledFor, actualAt: log.actionedAt, status: status))
        }
        // Derived misses — the SAME source Week reads, so the Missed filter matches Week's count.
        for slot in AdherenceCalculator.missedEvents(medicines: meds, logs: logSnaps, from: from, to: now, now: now) {
            events.append(HistoryEvent(id: "missed-\(slot.id)", medicineID: slot.medicineID,
                                       medicineName: slot.medicineName, dosage: slot.dosage,
                                       scheduledFor: slot.scheduledFor, actualAt: nil, status: .missed))
        }

        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = events.filter { event in
            (filter.status == nil || event.status == filter.status) &&
            (q.isEmpty || event.medicineName.lowercased().contains(q))
        }

        // Group by the dose's day; days newest → oldest, doses within a day oldest → newest (agenda order).
        let byDay = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.scheduledFor) }
        return byDay.keys.sorted(by: >).map { day in
            DayGroup(day: day, events: byDay[day]!.sorted { $0.scheduledFor < $1.scheduledFor })
        }
    }

    private func status(for action: DoseAction) -> DoseStatus? {
        switch action {
        case .taken: .taken
        case .skipped: .skipped
        case .snoozed: .snoozed
        }
    }

    private func dayLabel(_ day: Date, now: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }
}

/// One derived history event — a real action or a computed miss. Never persisted; assembled at read time.
private struct HistoryEvent: Identifiable {
    let id: String
    let medicineID: UUID
    let medicineName: String
    let dosage: String?
    let scheduledFor: Date
    let actualAt: Date?      // when acted (taken/skipped/snoozed); nil for a derived miss
    let status: DoseStatus
}

private struct HistoryEventRow: View {
    let event: HistoryEvent

    var body: some View {
        HStack(spacing: DoseSpacing.md) {
            Image(systemName: DoseTheme.icon(for: event.status))
                .font(.title3)
                .foregroundStyle(DoseTheme.color(for: event.status))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var title: String {
        if let dosage = event.dosage, !dosage.isEmpty { return "\(event.medicineName) · \(dosage)" }
        return event.medicineName
    }

    /// The status word (so every row states Taken/Skipped/Snoozed/Missed now that the pill is gone),
    /// the scheduled time, and the actual action time when it differs (a late take, a skip, a snooze).
    private var subtitle: String {
        let scheduled = event.scheduledFor.formatted(date: .omitted, time: .shortened)
        let status = DoseTheme.label(for: event.status)   // "Taken" / "Skipped" / "Snoozed" / "Missed"
        guard let actualAt = event.actualAt,
              abs(actualAt.timeIntervalSince(event.scheduledFor)) >= 60 else {
            return "\(status) · \(scheduled)"
        }
        let acted = actualAt.formatted(date: .omitted, time: .shortened)
        return "\(status) · scheduled \(scheduled), logged \(acted)"
    }
}
