import SwiftUI
import SwiftData

/// Manual entry (free, offline). The user types their own data, so there's no AI draft to verify —
/// the form *is* the confirm step. A new medicine saves straight from here (no redundant Review
/// screen); an existing medicine (edit) saves in place. The Review gate is reserved for the
/// AI-text and Scan paths, where a machine-proposed draft genuinely needs human confirmation.
struct ManualEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismissFlow) private var dismissFlow
    @AppStorage(SettingsKeys.escalationEnabled) private var escalationEnabled = false

    let editing: Medicine?
    @State private var draft: EditableDraft
    @State private var savedMedicine: Medicine?   // add-mode: the just-created med → push extras
    @State private var isSaving = false           // in-flight guard so a double-tap can't create two meds

    init(editing: Medicine? = nil) {
        self.editing = editing
        _draft = State(initialValue: editing.map { EditableDraft(editing: $0) } ?? .empty())
    }

    var body: some View {
        Form {
            // Same labeled "Details" styling as the Review gate (Name / Dosage / Form / Quantity),
            // so the one manual screen reads as a polished form, not a plain stack of inputs.
            Section("Details") {
                DraftDetailFields(draft: draft)
            }
            DraftScheduleEditor(draft: draft)
            // Editing is complete on one screen (icon/colour, treatment length, instructions). New
            // entry keeps these out of the primary form — they're offered as a post-save extras step.
            if editing != nil {
                MedicineExtrasEditor(draft: draft)
            }
        }
        .navigationTitle(editing == nil ? "New medicine" : "Edit medicine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editing != nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismissFlow() } }
            }
        }
        .navigationDestination(isPresented: extrasBinding) {
            if let medicine = savedMedicine { PostSaveExtrasView(medicine: medicine) }
        }
        .safeAreaInset(edge: .bottom) { cta }
    }

    private var extrasBinding: Binding<Bool> {
        Binding(get: { savedMedicine != nil }, set: { if !$0 { savedMedicine = nil } })
    }

    private var cta: some View {
        Button(action: save) {
            Text(editing == nil ? "Add medicine" : "Save")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(draft.blocksConfirm || isSaving)   // A1 (complete schedule) + B2 (no double-save)
        .accessibilityIdentifier("manualSave")
        .padding()
        .background(.bar)
    }

    /// Persist directly — new drafts are confirmed here, edits are applied in place. A new medicine
    /// then offers the optional post-save extras step; an edit (which already shows the extras inline)
    /// just closes the flow.
    private func save() {
        guard !isSaving else { return }   // guard the fast-double-tap window before navigation commits
        isSaving = true
        if let editing {
            MedicineWriter.saveEdit(editing, draft: draft, context: context, escalationEnabled: escalationEnabled)
            dismissFlow()
        } else {
            let created = MedicineWriter.confirm([draft], context: context, escalationEnabled: escalationEnabled)
            if let medicine = created.first {
                savedMedicine = medicine          // push the "almost done" extras step
            } else {
                dismissFlow()
            }
        }
    }
}

/// Times + repeat editor, shared by manual entry and review. "Times" = times of day; "Repeat" = how
/// often — kept as two clearly separated sections.
struct DraftScheduleEditor: View {
    @Bindable var draft: EditableDraft

    /// A dose-time binding keyed by row id, not array index: the getter/setter look the row up each
    /// time and no-op if it was deleted, so a row torn down mid-delete can never fault on a stale index.
    private func timeBinding(for id: UUID) -> Binding<Date> {
        Binding(
            get: { draft.timedDoses.first(where: { $0.id == id })?.time ?? .now },
            set: { newValue in
                if let i = draft.timedDoses.firstIndex(where: { $0.id == id }) {
                    draft.timedDoses[i].time = newValue
                }
            }
        )
    }

    var body: some View {
        Section {
            // A flagged (inferred / low-confidence) schedule WARNS and blocks Confirm until the user
            // edits the times or taps "Looks right" — the same acknowledge treatment name/dosage use, so
            // a guessed cadence can't be confirmed by inertia. Placed at the TOP of the times, right by
            // what it's about. Manual drafts are never flagged.
            if draft.mustReview("schedule") {
                HStack(spacing: 8) {
                    Label("Please review these times — adjust them or confirm they're right.",
                          systemImage: "exclamationmark.circle.fill")
                        .font(.caption).foregroundStyle(.red)
                    Spacer(minLength: 8)
                    Button("Looks right") { draft.acknowledge("schedule") }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            } else if draft.wasAcknowledged("schedule") {
                Label("Reviewed", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }
            // Stable per-row identity + a by-id binding (never an index subscript), so deleting a row
            // can't leave a torn-down DatePicker reading an out-of-bounds element and crashing.
            ForEach(Array(draft.timedDoses.enumerated()), id: \.element.id) { index, dose in
                DatePicker("Dose \(index + 1)",
                           selection: timeBinding(for: dose.id),
                           displayedComponents: .hourAndMinute)
            }
            .onDelete { offsets in
                draft.timedDoses.remove(atOffsets: offsets)
                if draft.timedDoses.isEmpty { draft.timedDoses = [TimedDose(time: .now)] }
            }
            Button {
                draft.timedDoses.append(TimedDose(time: draft.timedDoses.last?.time ?? .now))
            } label: {
                Label("Add time", systemImage: "plus")
            }
        } header: {
            Text("Times of day")
        } footer: {
            Text("One or more times to take it each scheduled day.")
        }
        // Editing the times or repeat counts as reviewing them — clears any must-review schedule flag
        // (no-op when there is none), mirroring how editing a name/dosage clears its flag.
        .onChange(of: draft.times) { draft.markEdited("schedule") }
        .onChange(of: draft.repeatMode) { draft.markEdited("schedule") }
        .onChange(of: draft.weekdays) { draft.markEdited("schedule") }
        .onChange(of: draft.intervalDays) { draft.markEdited("schedule") }
        .onChange(of: draft.daysOfMonth) { draft.markEdited("schedule") }

        Section {
            Picker("Repeat", selection: $draft.repeatMode) {
                ForEach(EditableDraft.RepeatMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            switch draft.repeatMode {
            case .everyday:
                EmptyView()
            case .weekdays:
                WeekdayPicker(selection: $draft.weekdays)
            case .everyNDays:
                Stepper("Every \(draft.intervalDays) days", value: $draft.intervalDays, in: 2...30)
            case .daysOfMonth:
                MonthDayPicker(selection: $draft.daysOfMonth)
            }
        } header: {
            Text("Repeat")
        } footer: {
            if draft.scheduleIncomplete {
                Text(draft.repeatMode == .weekdays
                     ? "Select at least one weekday, or choose a different repeat."
                     : "Select at least one day of the month, or choose a different repeat.")
            } else {
                Text("How often the dose recurs.")
            }
        }

    }
}

/// Compact S–M–T–W–T–F–S selector mapping to Calendar weekday numbers (1 = Sunday).
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let symbols = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...7, id: \.self) { weekday in
                let on = selection.contains(weekday)
                Button {
                    if on { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(symbols[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Compact 1–31 day-of-month multi-select.
struct MonthDayPicker: View {
    @Binding var selection: Set<Int>
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(1...31, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text("\(day)")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
