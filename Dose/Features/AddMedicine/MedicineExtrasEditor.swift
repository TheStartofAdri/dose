import SwiftUI

/// Reusable optional-extras controls bound to an `EditableDraft`: icon + colour, treatment length,
/// and instructions. Emits `Section`s so it can drop into a `Form` (the post-save extras step and
/// the edit form). Nothing here is required — every control has a sensible default.
struct MedicineExtrasEditor: View {
    @Bindable var draft: EditableDraft

    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
    private let colorColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        Section("Icon & colour") {
            LazyVGrid(columns: iconColumns, spacing: 10) {
                ForEach(MedAppearance.icons, id: \.self) { icon in
                    let selected = (draft.iconName ?? MedAppearance.defaultIcon) == icon
                    Button {
                        draft.iconName = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.system(size: 18))
                            .frame(width: 40, height: 40)
                            .foregroundStyle(selected ? .white : .primary)
                            .background(selected ? MedAppearance.color(draft.colorHex) : Color.secondary.opacity(0.15),
                                        in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Icon \(icon)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)

            LazyVGrid(columns: colorColumns, spacing: 12) {
                ForEach(MedAppearance.colors, id: \.self) { hex in
                    let selected = draft.colorHex == hex
                    Button {
                        draft.colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.primary, lineWidth: selected ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Colour \(hex)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }

        Section {
            Picker("Treatment length", selection: $draft.durationMode) {
                ForEach(EditableDraft.DurationMode.allCases) { mode in
                    Text(mode.shortLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            switch draft.durationMode {
            case .ongoing:
                EmptyView()
            case .days:
                Stepper("For \(draft.durationDays) day\(draft.durationDays == 1 ? "" : "s")",
                        value: $draft.durationDays, in: 1...365)
            case .until:
                DatePicker("Ends on", selection: $draft.endDateChoice,
                           in: Date()..., displayedComponents: .date)
            }
        } header: {
            Text("Treatment length")
        } footer: {
            Text("Ongoing keeps reminding you. A finite course stops reminders after it ends and won't count later days against your adherence.")
        }

        Section {
            Picker("Remind me before", selection: $draft.leadTimeMinutes) {
                Text("At dose time").tag(Int?.none)
                Text("5 minutes before").tag(Int?(5))
                Text("10 minutes before").tag(Int?(10))
                Text("15 minutes before").tag(Int?(15))
                Text("30 minutes before").tag(Int?(30))
            }
        } header: {
            Text("Heads-up reminder")
        } footer: {
            Text("Optionally send one extra reminder a few minutes before each dose. The on-time reminder is always sent.")
        }

        refillSection

        Section("Instructions") {
            TextField("e.g. take with food, finish the course", text: $draft.instructions, axis: .vertical)
                .lineLimit(1...4)
                .textInputAutocapitalization(.sentences)
        }
    }

    @ViewBuilder private var refillSection: some View {
        Section {
            Toggle("Remind me to refill", isOn: $draft.refillTrackingOn)
            if draft.refillTrackingOn {
                Stepper("\(draft.unitsPerDose) per dose", value: $draft.unitsPerDose, in: 1...20)
                Stepper("Remind when ~\(draft.refillThresholdDays) day\(draft.refillThresholdDays == 1 ? "" : "s") left",
                        value: $draft.refillThresholdDays, in: 1...60)
                packCountControls
            }
        } header: {
            Text("Refill reminder")
        } footer: {
            Text(draft.refillTrackingOn
                 ? "Dose estimates how many days you have left from your schedule and reminds you before you run out."
                 : "Track your pack and get a heads-up before you run out.")
        }
        // A new medicine needs a starting pack size the moment tracking is enabled; an edit keeps its
        // existing count until you explicitly set a new one.
        .onChange(of: draft.refillTrackingOn) { _, on in
            if on && !draft.isEditingExisting && draft.refillNewStock == nil { draft.refillNewStock = 30 }
        }
    }

    @ViewBuilder private var packCountControls: some View {
        if let stock = draft.refillNewStock {
            Stepper("Pack size: \(stock)", value: Binding(get: { stock }, set: { draft.refillNewStock = $0 }), in: 0...500)
            if draft.isEditingExisting {
                Button("Keep current count instead") { draft.refillNewStock = nil }
                    .font(.callout)
            }
        } else {
            // Editing with no new count queued → the current stock is preserved; offer to update it.
            LabeledContent("Pack size", value: "Keeping current count")
            Button("Set current pack count") { draft.refillNewStock = draft.refillStartingStock }
        }
    }
}
