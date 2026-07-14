import SwiftUI
import SwiftData

/// Execution Mode — the main product. Fast, deterministic, offline. Reads only confirmed data,
/// asks no questions, and never touches the network or AI.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Medicine.name) private var medicines: [Medicine]
    @Query(sort: \DoseLog.scheduledFor) private var logs: [DoseLog]
    @Query(sort: \TrackedMetric.sortOrder) private var metrics: [TrackedMetric]
    @AppStorage(SettingsKeys.escalationEnabled) private var escalationEnabled = false

    @State private var showingAdd = false
    @State private var editingMedicine: Medicine?
    @State private var archiving: Medicine?
    @State private var deleting: Medicine?
    @State private var detailMedicine: Medicine?
    @State private var actionSheetDose: TodayDose?
    @State private var actionError: String?
    @State private var showingMetrics = false
    @State private var loggingMetric: TrackedMetric?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                content(now: timeline.date)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingMetrics = true } label: { Image(systemName: "heart.text.square") }
                        .accessibilityLabel("Track symptoms and vitals")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add medicine")
                }
            }
            .sheet(isPresented: $showingAdd) { AddMedicineFlow() }
            .sheet(isPresented: editBinding) {
                if let medicine = editingMedicine { AddMedicineFlow(editing: medicine) }
            }
            .navigationDestination(isPresented: detailBinding) {
                if let medicine = detailMedicine { MedicineDetailView(medicine: medicine) }
            }
            .sheet(item: $actionSheetDose) { dose in
                DoseActionSheet(
                    dose: dose,
                    onTake: { record(.taken, for: dose) },
                    onSkip: { record(.skipped, for: dose) },
                    onSnooze: { minutes in record(.snoozed, for: dose, minutes: minutes) }
                )
            }
            .alert("Couldn't save that dose", isPresented: actionErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "Please try again.")
            }
            .sheet(isPresented: $showingMetrics) { MetricsView() }
            .sheet(item: $loggingMetric) { LogMetricSheet(metric: $0) }
        }
    }

    /// A gentle "today's check-ins" prompt: active metrics not yet logged today, as tappable chips.
    /// Renders nothing when there are no metrics (or all are logged), so it never adds space — or
    /// affects the Today card geometry — for medication-only users.
    @ViewBuilder
    private func checkInsSection(now: Date) -> some View {
        let due = TrackedMetric.active(metrics).filter { !$0.hasEntryToday(now: now) }
        if !due.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("Today's check-ins")
                    .padding(.horizontal, 16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DoseSpacing.sm) {
                        ForEach(due) { metric in
                            Button { loggingMetric = metric } label: {
                                HStack(spacing: 6) {
                                    MedicineIconBadge(iconName: metric.iconName, colorHex: metric.colorHex, size: 22)
                                    Text(metric.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(DoseColors.cardBackground, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Log \(metric.name)")
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let doses = ExecutionEngine.todaysDoses(confirmedMedicines: medicines, logs: logs, now: now)
        if doses.isEmpty {
            if Medicine.activeConfirmed(medicines).isEmpty {
                emptyState                       // genuinely no medicines yet
            } else {
                // Has active medicines, just none due today (specific weekdays / every-N-days / a
                // finished course) — a rest day, NOT an empty app. Keep the date + streak header.
                VStack(spacing: 0) {
                    header(now: now)
                    restDayState
                }
            }
        } else {
            VStack(spacing: 0) {
                header(now: now)
                if NotificationStatus.shared.hasNotice {
                    NotificationNoticeBanner(style: .card)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                // "Next up" hero: the soonest un-acted dose, with a prominent Take + 10-min Snooze.
                if let nextUp = doses.first(where: { !$0.status.isSettled }) {
                    NextUpCard(
                        dose: nextUp,
                        onTake: { record(.taken, for: nextUp) },
                        onSnooze: { actionSheetDose = nextUp },
                        onOpenDetail: { if let medicine = medicine(for: nextUp) { detailMedicine = medicine } }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                checkInsSection(now: now)
                SectionHeader("Today's schedule")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                List {
                    ForEach(doses) { dose in
                        DoseCardView(
                            dose: dose,
                            iconName: medicine(for: dose)?.iconName,
                            colorHex: medicine(for: dose)?.colorHex,
                            instructions: medicine(for: dose)?.instructions,
                            onTake: { record(.taken, for: dose) },
                            onUndo: { undo(for: dose) },
                            onEdit: { beginEdit(dose) },
                            onArchive: { if let medicine = medicine(for: dose) { archiving = medicine } },
                            onDelete: { if let medicine = medicine(for: dose) { deleting = medicine } },
                            onOpenDetail: { if let medicine = medicine(for: dose) { detailMedicine = medicine } }
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                        // Simple, non-conflicting gestures: right = Take, left = Skip today. Settled
                        // rows get neither — a second swipe would stack a contradictory log on the
                        // slot (take-then-skip); the card's Undo is the correction path.
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if !dose.status.isSettled {
                                Button { record(.taken, for: dose) } label: { Label("Take", systemImage: "checkmark") }
                                    .tint(DoseColors.taken)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if !dose.status.isSettled {
                                Button { record(.skipped, for: dose) } label: { Label("Skip today", systemImage: "minus.circle") }
                                    .tint(DoseColors.neutralSolid)
                            }
                        }
                        // Per-row confirmations so the popover anchors to the exact card whose ⋯ was tapped.
                        .confirmationDialog("Archive this medicine?", isPresented: archiveRowBinding(dose), presenting: archiving) { medicine in
                            Button("Archive \(medicine.name)", role: .destructive) { archive(medicine) }
                            Button("Cancel", role: .cancel) {}
                        } message: { _ in
                            Text("It stops reminding you and leaves Today. Your dose history is kept.")
                        }
                        .confirmationDialog("Delete permanently?", isPresented: deleteRowBinding(dose), presenting: deleting) { medicine in
                            Button("Delete \(medicine.name)", role: .destructive) { deletePermanently(medicine) }
                            Button("Cancel", role: .cancel) {}
                        } message: { _ in
                            Text("Removes the medicine and its schedule. Past dose history is still kept for your records.")
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func header(now: Date) -> some View {
        let streak = currentStreak(now: now)
        return HStack(alignment: .firstTextBaseline) {
            Text(now, format: .dateTime.weekday(.wide).month().day())
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            if streak > 0 {
                Label("\(streak) day\(streak == 1 ? "" : "s")", systemImage: "flame.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            DoseEmptyState(icon: "pills.fill",
                           title: "No medicines yet",
                           message: "Add your first medicine to start tracking doses.") {
                Button { showingAdd = true } label: {
                    Label("Add medicine", systemImage: "plus").font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
    }

    /// Shown when the user HAS active medicines but none are scheduled today — a rest day, distinct from
    /// the "no medicines yet" first-run state so a real user isn't told to add their first medicine.
    private var restDayState: some View {
        VStack {
            Spacer()
            DoseEmptyState(icon: "checkmark.circle",
                           title: "Nothing scheduled today",
                           message: "You have no doses due today. Your schedule picks back up automatically.")
            Spacer()
        }
    }

    // MARK: - Actions

    private func record(_ action: DoseAction, for dose: TodayDose, minutes: Int? = nil) {
        let snoozeMinutes = action == .snoozed ? (minutes ?? 10) : nil
        // `context` is the injected main (observed) context, so the @Query updates live. Only proceed to
        // cancel the reminder + show success once the save actually persisted (C2): a failed write leaves
        // the reminder intact and surfaces an error instead of a false "done".
        do {
            try DoseActionWriter.record(action, medicineID: dose.medicineID, medicineName: dose.medicineName,
                                        dosage: dose.dosage, scheduledFor: dose.scheduledFor,
                                        snoozeMinutes: snoozeMinutes, into: context)
        } catch {
            Haptics.error()
            actionError = "Couldn't save that dose. Please try again."
            return
        }

        switch action {
        case .taken:
            Haptics.success()
            NotificationScheduler.shared.cancelSlot(medicineID: dose.medicineID, scheduledFor: dose.scheduledFor)
        case .skipped:
            Haptics.light()
            NotificationScheduler.shared.cancelSlot(medicineID: dose.medicineID, scheduledFor: dose.scheduledFor)
        case .snoozed:
            Haptics.light()
            NotificationScheduler.shared.cancelSlot(medicineID: dose.medicineID, scheduledFor: dose.scheduledFor)
            NotificationScheduler.shared.scheduleSnooze(
                medicineID: dose.medicineID, medicineName: dose.medicineName, dosage: dose.dosage,
                scheduledFor: dose.scheduledFor, minutes: snoozeMinutes)
        }
    }

    /// Undo an accidental Take/Skip: remove the log(s) for that slot so it reverts to its computed
    /// state (due/upcoming/missed). A false "taken" on a med tracker is unsafe, so this is one tap.
    /// Also re-plans, so the one-shot reminder the take/skip cancelled comes back if the slot is still
    /// in the future (a past slot isn't rescheduled).
    private func undo(for dose: TodayDose) {
        let removed = DoseUndo.undo(medicineID: dose.medicineID, scheduledFor: dose.scheduledFor,
                                    context: context, escalationEnabled: escalationEnabled)
        if removed > 0 { Haptics.light() }
    }

    private func currentStreak(now: Date) -> Int {
        let meds = Medicine.activeConfirmed(medicines).map { $0.snapshot() }
        return StreakCalculator.currentStreak(medicines: meds, logs: logs.map { $0.snapshot() }, now: now)
    }

    private func beginEdit(_ dose: TodayDose) {
        editingMedicine = medicine(for: dose)
    }

    private func medicine(for dose: TodayDose) -> Medicine? {
        medicines.first { $0.id == dose.medicineID }
    }

    /// Archive: deactivate so it leaves Today and its reminders are cancelled, but keep DoseLog history.
    private func archive(_ medicine: Medicine) {
        MedicineWriter.setArchived(medicine, true, context: context, escalationEnabled: escalationEnabled)
    }

    /// Delete the medicine + its schedule. DoseLog history has no relationship to Medicine, so it survives.
    private func deletePermanently(_ medicine: Medicine) {
        // Clear the stored reference BEFORE deleting: the per-row confirmation bindings read `deleting?.id`,
        // and the delete's save re-fires the @Query — reading an invalidated @Model there is a SwiftData
        // fatal error (the same hazard MedicineDetailView guards by dismissing first) (B1).
        deleting = nil
        MedicineWriter.deletePermanently(medicine, context: context, escalationEnabled: escalationEnabled)
    }

    private var editBinding: Binding<Bool> {
        Binding(get: { editingMedicine != nil }, set: { if !$0 { editingMedicine = nil } })
    }
    /// Per-row bindings: only the row whose medicine matches the pending archive/delete presents,
    /// so the confirmation popover anchors to that exact card.
    private func archiveRowBinding(_ dose: TodayDose) -> Binding<Bool> {
        Binding(get: { archiving?.id == dose.medicineID }, set: { if !$0 { archiving = nil } })
    }
    private func deleteRowBinding(_ dose: TodayDose) -> Binding<Bool> {
        Binding(get: { deleting?.id == dose.medicineID }, set: { if !$0 { deleting = nil } })
    }
    private var detailBinding: Binding<Bool> {
        Binding(get: { detailMedicine != nil }, set: { if !$0 { detailMedicine = nil } })
    }
}
