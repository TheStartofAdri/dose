import SwiftUI
import SwiftData

/// The Week tab (premium): weekly adherence analytics derived entirely from `AdherenceCalculator` — a
/// ring + Taken/Skipped/Snoozed/Total tiles, the "missed this week" list, a 14-day chart, and a
/// per-medicine breakdown. Reads the SAME source as History, so Week's missed count and History's
/// "Missed" filter can never disagree (locked by `testMissedEventsMatchMissedCountForTheSameWindow`).
///
/// Gated behind `Entitlements.isPremium`: a lapsed subscriber sees an unlock state, not a broken tab.
/// (New users can't reach the app at all without an active trial/subscription — the entry paywall.)
struct WeekView: View {
    @Query(sort: \Medicine.name) private var medicines: [Medicine]
    @Query(sort: \DoseLog.scheduledFor) private var logs: [DoseLog]
    @ObservedObject private var subscription = SubscriptionStore.shared   // re-render on entitlement change

    @State private var weekOffset = 0
    @State private var showPaywall = false
    @State private var selectedMedicine: Medicine?

    var body: some View {
        NavigationStack {
            Group {
                if Entitlements.isPremium {
                    TimelineView(.periodic(from: .now, by: 300)) { timeline in
                        content(now: timeline.date)
                    }
                } else {
                    locked
                }
            }
            .navigationTitle("This Week")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $selectedMedicine) { MedicineDetailView(medicine: $0) }
            .sheet(isPresented: $showPaywall) { PaywallView(context: .unlock(.weeklyView)) }
        }
    }

    // MARK: - Premium content

    @ViewBuilder
    private func content(now: Date) -> some View {
        let cal = Calendar.current
        let interval = cal.dateInterval(of: .weekOfYear, for: base(now: now, cal: cal))
            ?? DateInterval(start: cal.startOfDay(for: now), duration: 7 * 86_400)
        let weekStart = interval.start
        let weekEnd = cal.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end

        let meds = Medicine.activeConfirmed(medicines).map { $0.snapshot() }
        let logSnaps = logs.map { $0.snapshot() }
        let weekDays = AdherenceCalculator.days(medicines: meds, logs: logSnaps, from: weekStart, to: weekEnd, now: now)
        let rate = AdherenceCalculator.rate(weekDays)
        let taken = weekDays.reduce(0) { $0 + $1.taken }
        let skipped = weekDays.reduce(0) { $0 + $1.skipped }
        let missed = AdherenceCalculator.missedCount(weekDays)
        let snoozed = logSnaps.filter { $0.action == .snoozed && $0.scheduledFor >= weekStart && $0.scheduledFor <= weekEnd }.count
        let total = taken + skipped + missed
        let missedList = AdherenceCalculator.missedEvents(medicines: meds, logs: logSnaps, from: weekStart, to: weekEnd, now: now)
        let chart14 = AdherenceCalculator.days(medicines: meds, logs: logSnaps, now: now, days: 14)

        ScrollView {
            VStack(spacing: DoseSpacing.lg) {
                switcher(weekStart: weekStart, weekEnd: weekEnd)
                if meds.isEmpty {
                    DoseEmptyState(icon: "calendar",
                                   title: "No data yet",
                                   message: "Weekly stats appear once you're tracking medicines.")
                        .doseCardStyle()
                } else {
                    StreakBanner(streak: StreakCalculator.currentStreak(medicines: meds, logs: logSnaps, now: now))
                    adherenceCard(rate: rate)
                    tiles(taken: taken, skipped: skipped, snoozed: snoozed, total: total)
                    missedSection(missedList)
                    AdherenceChartCard(days: chart14)
                    byMedicineSection(from: weekStart, to: weekEnd, now: now, logs: logSnaps)
                }
            }
            .padding(DoseSpacing.lg)
        }
        .background(DoseColors.groupedBackground)
    }

    private func base(now: Date, cal: Calendar) -> Date {
        cal.date(byAdding: .weekOfYear, value: weekOffset, to: now) ?? now
    }

    // MARK: Sections

    private func switcher(weekStart: Date, weekEnd: Date) -> some View {
        HStack {
            Button { weekOffset -= 1 } label: {
                Image(systemName: "chevron.left").font(.headline)
            }
            .accessibilityLabel("Previous week")
            Spacer()
            VStack(spacing: 2) {
                Text(label(for: weekOffset)).font(.caption).foregroundStyle(.secondary)
                Text("\(weekStart.formatted(.dateTime.month().day())) – \(weekEnd.formatted(.dateTime.month().day()))")
                    .font(.headline)
            }
            Spacer()
            Button { weekOffset += 1 } label: {
                Image(systemName: "chevron.right").font(.headline)
            }
            .accessibilityLabel("Next week")
        }
        .padding(.horizontal, DoseSpacing.xs)
    }

    private func label(for offset: Int) -> String {
        switch offset {
        case 0: "This week"
        case -1: "Last week"
        case 1: "Next week"
        case ..<0: "\(-offset) weeks ago"
        default: "In \(offset) weeks"
        }
    }

    private func adherenceCard(rate: Double?) -> some View {
        HStack(spacing: DoseSpacing.lg) {
            AdherenceRing(rate: rate)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline(for: rate)).font(.headline)
                Text(subtitle(for: rate)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .doseCardStyle()
    }

    private func headline(for rate: Double?) -> String {
        guard let rate else { return "No doses due" }
        switch rate {
        case 0.9...: return "Great job!"
        case 0.7..<0.9: return "Solid week"
        case 0.5..<0.7: return "Keep at it"
        default: return "Let's turn it around"
        }
    }

    private func subtitle(for rate: Double?) -> String {
        rate == nil ? "Nothing was scheduled and due this week."
                    : "You're building a strong habit."
    }

    private func tiles(taken: Int, skipped: Int, snoozed: Int, total: Int) -> some View {
        HStack {
            // Only colour a non-zero count — a "0 Snoozed" shouldn't draw the eye in blue.
            StatTile(value: "\(taken)", label: "Taken", tint: taken > 0 ? DoseColors.taken : DoseColors.neutral)
            StatTile(value: "\(skipped)", label: "Skipped")
            StatTile(value: "\(snoozed)", label: "Snoozed", tint: snoozed > 0 ? DoseColors.snoozed : DoseColors.neutral)
            StatTile(value: "\(total)", label: "Total")
        }
        .doseCardStyle()
    }

    private func missedSection(_ missed: [ScheduledSlot]) -> some View {
        VStack(alignment: .leading, spacing: DoseSpacing.sm) {
            SectionHeader(missed.isEmpty ? "Nothing missed this week" : "Missed this week")
            if missed.isEmpty {
                Text("Every past-due dose was taken or skipped.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(missed) { slot in
                    HStack(spacing: DoseSpacing.sm) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(DoseColors.missed)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(slot.medicineName).font(.subheadline.weight(.medium))
                            Text(slot.scheduledFor.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute()))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .doseCardStyle()
    }

    private func byMedicineSection(from: Date, to: Date, now: Date, logs: [DoseLogSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: DoseSpacing.md) {
            SectionHeader("By medicine")
            ForEach(Medicine.activeConfirmed(medicines)) { med in
                let rate = AdherenceCalculator.rate(
                    AdherenceCalculator.days(medicines: [med.snapshot()], logs: logs, from: from, to: to, now: now))
                Button { selectedMedicine = med } label: {
                    HStack(spacing: DoseSpacing.md) {
                        MedicineIconBadge(iconName: med.iconName, colorHex: med.colorHex, size: 34)
                        Text(med.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        Text(rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(rate == nil ? .secondary : .primary)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .doseCardStyle()
    }

    // MARK: - Locked (lapsed subscriber)

    private var locked: some View {
        DoseEmptyState(icon: "chart.bar.xaxis",
                       title: "Weekly Overview",
                       message: "See your weekly adherence, missed doses, and 14-day trend. Included with Dose Premium.") {
            Button("Unlock Weekly Overview") { showPaywall = true }
                .font(.headline)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }
}
