import SwiftUI
import SwiftData

/// The screen users reach by tapping a dose card. Shows the medicine's details, its schedule, and
/// its OWN adherence history (same corrected `AdherenceCalculator` source as the History tab), with
/// Edit / Archive / Delete available from the toolbar menu.
struct MedicineDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.escalationEnabled) private var escalationEnabled = false

    let medicine: Medicine
    @Query(sort: \DoseLog.scheduledFor) private var allLogs: [DoseLog]

    @State private var showEdit = false
    @State private var confirmArchive = false
    @State private var confirmDelete = false
    @State private var showReport = false
    @State private var showPaywall = false
    @State private var actionSheetDose: TodayDose?
    @ObservedObject private var subscription = SubscriptionStore.shared   // re-render on entitlement change

    var body: some View {
        // A permanent delete invalidates `medicine` while this view is still mid-pop: dismiss() only
        // STARTS the animation, and the delete's save re-fires `allLogs`/observation during it —
        // rendering an invalidated @Model (navigationTitle reads `medicine.name`) is a SwiftData
        // fatal error. Render nothing for the remaining frames instead.
        if medicine.isDeleted {
            Color.clear
        } else {
            detailBody
        }
    }

    private var detailBody: some View {
        TimelineView(.periodic(from: .now, by: 300)) { timeline in
            content(now: timeline.date)
        }
        .navigationTitle(medicine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                    Button {
                        if Entitlements.isPremium { showReport = true } else { showPaywall = true }
                    } label: { Label("Export report", systemImage: "square.and.arrow.up") }
                    Button { confirmArchive = true } label: { Label("Archive", systemImage: "archivebox") }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete permanently", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Manage medicine")
            }
        }
        .sheet(isPresented: $showEdit) { AddMedicineFlow(editing: medicine) }
        .sheet(isPresented: $showReport) {
            // Single-medicine report — pre-selected to this medicine.
            NavigationStack { ReportOptionsView(preselected: [medicine.id]) }
        }
        .sheet(isPresented: $showPaywall) { PaywallView(context: .unlock(.reportExport)) }
        .sheet(item: $actionSheetDose) { dose in
            DoseActionSheet(
                dose: dose,
                onTake: { record(.taken, for: dose) },
                onSkip: { record(.skipped, for: dose) },
                onSnooze: { minutes in record(.snoozed, for: dose, minutes: minutes) }
            )
        }
        .confirmationDialog("Archive this medicine?", isPresented: $confirmArchive) {
            Button("Archive \(medicine.name)", role: .destructive) { archive() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It stops reminding you and leaves Today. Your dose history is kept.")
        }
        .confirmationDialog("Delete permanently?", isPresented: $confirmDelete) {
            Button("Delete \(medicine.name)", role: .destructive) { deletePermanently() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the medicine and its schedule. Past dose history is still kept for your records.")
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let medLogs = allLogs.filter { $0.medicineID == medicine.id }.map { $0.snapshot() }
        let series = AdherenceCalculator.days(medicines: [medicine.snapshot()], logs: medLogs, now: now, days: 30)
        let last14 = Array(series.suffix(14))
        let last7 = Array(series.suffix(7))
        // This medicine's soonest un-acted dose today — the one the action sheet logs.
        let todaysDose = ExecutionEngine.todaysDoses(confirmedMedicines: [medicine], logs: allLogs, now: now)
            .first { !$0.status.isSettled }

        List {
            Section {
                HStack(spacing: 14) {
                    MedicineIconBadge(iconName: medicine.iconName, colorHex: medicine.colorHex, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(medicine.name).font(.title3.weight(.semibold))
                        if let dosage = medicine.dosage, !dosage.isEmpty {
                            Text(dosage).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if let todaysDose {
                Section("Today") {
                    Button { actionSheetDose = todaysDose } label: {
                        HStack(spacing: 12) {
                            Image(systemName: DoseTheme.icon(for: todaysDose.status))
                                .foregroundStyle(DoseTheme.color(for: todaysDose.status))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Due \(todaysDose.scheduledFor.formatted(date: .omitted, time: .shortened))")
                                    .foregroundStyle(.primary)
                                Text("Tap to log this dose").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Log today's dose for \(medicine.name)")
                }
            }

            Section("Details") {
                if let form = medicine.form, !form.isEmpty { LabeledContent("Form", value: form) }
                if let quantity = medicine.quantity, !quantity.isEmpty { LabeledContent("Pack size", value: quantity) }
                LabeledContent("Status", value: medicine.isActive ? "Active" : "Archived")
                if let instructions = medicine.instructions,
                   !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Instructions").font(.caption).foregroundStyle(.secondary)
                        Text(instructions)
                    }
                }
            }

            Section("Schedule") {
                if medicine.doseTimes.isEmpty {
                    Text("No schedule set").foregroundStyle(.secondary)
                } else {
                    ForEach(sortedTimes, id: \.persistentModelID) { dt in
                        LabeledContent(timeString(dt), value: repeatSummary(dt))
                    }
                }
                LabeledContent("Treatment", value: treatmentSummary)
            }

            Section("Adherence") {
                HStack {
                    rateColumn("7-day", AdherenceCalculator.rate(last7))
                    Divider()
                    rateColumn("30-day", AdherenceCalculator.rate(series))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                // The chart card carries a fixed-height `Chart`; inside a `List` the self-sizing row
                // doesn't pick up that definite height on first layout and clips the card. Forcing the
                // ideal vertical size makes the row size to the full content (chart + legend), matching
                // how it renders in the History ScrollView.
                AdherenceChartCard(days: last14)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .listRowBackground(Color.clear)
            }
        }
    }

    private var sortedTimes: [DoseTime] {
        medicine.doseTimes.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    private var treatmentSummary: String {
        guard let endDate = medicine.endDate else { return "Ongoing" }
        return "Ends \(endDate.formatted(date: .abbreviated, time: .omitted))"
    }

    private func rateColumn(_ title: String, _ rate: Double?) -> some View {
        VStack(spacing: 2) {
            Text(rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                .font(.title2.weight(.bold)).monospacedDigit()
                .foregroundStyle(rate == nil ? .secondary : .primary)
            Text("\(title) adherence").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func timeString(_ dt: DoseTime) -> String {
        var c = DateComponents(); c.hour = dt.hour; c.minute = dt.minute
        let date = Calendar.current.date(from: c) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Human-readable repeat pattern, mirroring the DoseSlotRule precedence.
    private func repeatSummary(_ dt: DoseTime) -> String {
        if !dt.daysOfMonth.isEmpty {
            return "Days " + dt.daysOfMonth.sorted().map(String.init).joined(separator: ", ")
        }
        if dt.intervalDays >= 2 {
            return "Every \(dt.intervalDays) days"
        }
        if !dt.weekdays.isEmpty {
            let symbols = Calendar.current.shortWeekdaySymbols
            return dt.weekdays.sorted().compactMap { (1...7).contains($0) ? symbols[$0 - 1] : nil }.joined(separator: " ")
        }
        return "Every day"
    }

    /// Log a dose action for this medicine's today dose, mirroring `TodayView.record` (same writer +
    /// notification cancel/snooze), so logging from detail behaves identically to logging from Today.
    private func record(_ action: DoseAction, for dose: TodayDose, minutes: Int? = nil) {
        let snoozeMinutes = action == .snoozed ? (minutes ?? 10) : nil
        DoseActionWriter.record(action, medicineID: dose.medicineID, medicineName: dose.medicineName,
                                dosage: dose.dosage, scheduledFor: dose.scheduledFor,
                                snoozeMinutes: snoozeMinutes, into: context)
        NotificationScheduler.shared.cancelSlot(medicineID: dose.medicineID, scheduledFor: dose.scheduledFor)
        if action == .snoozed {
            NotificationScheduler.shared.scheduleSnooze(
                medicineID: dose.medicineID, medicineName: dose.medicineName, dosage: dose.dosage,
                scheduledFor: dose.scheduledFor, minutes: snoozeMinutes)
        }
        Haptics.light()
    }

    // MARK: - Management (mirrors Today's archive/delete: keep DoseLog history)

    private func archive() {
        MedicineWriter.setArchived(medicine, true, context: context, escalationEnabled: escalationEnabled)
        dismiss()
    }

    private func deletePermanently() {
        // Dismiss first so the view is torn down before its @Model reference is invalidated.
        dismiss()
        MedicineWriter.deletePermanently(medicine, context: context, escalationEnabled: escalationEnabled)
    }
}
