import SwiftUI
import SwiftData

/// Execution Mode — the main product. Fast, deterministic, offline. Reads only confirmed data,
/// asks no questions, and never touches the network or AI.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Medicine.name) private var medicines: [Medicine]
    @Query(sort: \DoseLog.scheduledFor) private var logs: [DoseLog]
    @AppStorage(SettingsKeys.escalationEnabled) private var escalationEnabled = false

    @State private var showingAdd = false
    @State private var showingWeek = false
    @State private var showWeekPaywall = false
    @ObservedObject private var subscription = SubscriptionStore.shared   // re-render on entitlement change
    @State private var editingMedicine: Medicine?
    @State private var archiving: Medicine?
    @State private var deleting: Medicine?
    @State private var detailMedicine: Medicine?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                content(now: timeline.date)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // "This week" is premium; non-subscribers get the unlock paywall (Today stays free).
                    Button {
                        if Entitlements.isPremium { showingWeek = true } else { showWeekPaywall = true }
                    } label: { Image(systemName: "calendar") }
                        .accessibilityLabel("This week")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add medicine")
                }
            }
            .navigationDestination(isPresented: $showingWeek) { WeekView() }
            .sheet(isPresented: $showWeekPaywall) { PaywallView(context: .unlock(.weeklyView)) }
            .sheet(isPresented: $showingAdd) { AddMedicineFlow() }
            .sheet(isPresented: editBinding) {
                if let medicine = editingMedicine { AddMedicineFlow(editing: medicine) }
            }
            .navigationDestination(isPresented: detailBinding) {
                if let medicine = detailMedicine { MedicineDetailView(medicine: medicine) }
            }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let doses = ExecutionEngine.todaysDoses(confirmedMedicines: medicines, logs: logs, now: now)
        if doses.isEmpty {
            emptyState
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
                        onSnooze: { record(.snoozed, for: nextUp) },
                        onOpenDetail: { if let medicine = medicine(for: nextUp) { detailMedicine = medicine } }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
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
                                    .tint(.green)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if !dose.status.isSettled {
                                Button { record(.skipped, for: dose) } label: { Label("Skip today", systemImage: "minus.circle") }
                                    .tint(.gray)
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
        ContentUnavailableView {
            Label("No medicines yet", systemImage: "pills.fill")
        } description: {
            Text("Add your first medicine to start tracking doses.")
        } actions: {
            Button { showingAdd = true } label: {
                Label("Add medicine", systemImage: "plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func record(_ action: DoseAction, for dose: TodayDose) {
        // `context` is the injected main (observed) context, so the @Query updates live.
        DoseActionWriter.record(action, medicineID: dose.medicineID, medicineName: dose.medicineName,
                                dosage: dose.dosage, scheduledFor: dose.scheduledFor, into: context)

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
                scheduledFor: dose.scheduledFor)
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
