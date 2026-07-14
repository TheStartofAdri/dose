import SwiftUI
import SwiftData

/// Create a `TrackedMetric` — a symptom (0–10) or a vital (number + unit). Common presets make it a
/// one-tap add; a custom form covers anything else. Consumer categories, not clinical codes.
struct AddMetricSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var metrics: [TrackedMetric]

    @State private var name = ""
    @State private var kind: MetricKind = .symptom
    @State private var unit = ""
    @State private var saveError = false

    struct Preset: Identifiable {
        let id = UUID()
        let name: String; let kind: MetricKind; let valueKind: MetricValueKind
        let unit: String?; let icon: String; let color: String
    }
    private let presets: [Preset] = [
        .init(name: "Pain", kind: .symptom, valueKind: .severity, unit: nil, icon: "bolt.fill", color: "#FF3B30"),
        .init(name: "Mood", kind: .symptom, valueKind: .severity, unit: nil, icon: "face.smiling", color: "#FF9500"),
        .init(name: "Energy", kind: .symptom, valueKind: .severity, unit: nil, icon: "sun.max.fill", color: "#FFCC00"),
        .init(name: "Sleep", kind: .vital, valueKind: .number, unit: "hrs", icon: "bed.double.fill", color: "#5856D6"),
        .init(name: "Weight", kind: .vital, valueKind: .number, unit: "kg", icon: "scalemass.fill", color: "#34C759"),
        .init(name: "Heart rate", kind: .vital, valueKind: .number, unit: "bpm", icon: "heart.fill", color: "#FF3B30"),
        .init(name: "Glucose", kind: .vital, valueKind: .number, unit: "mg/dL", icon: "drop.fill", color: "#FF2D55"),
        .init(name: "Oxygen", kind: .vital, valueKind: .number, unit: "%", icon: "lungs.fill", color: "#00C7BE"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick add") {
                    ForEach(presets) { preset in
                        Button {
                            create(name: preset.name, kind: preset.kind, valueKind: preset.valueKind,
                                   unit: preset.unit, icon: preset.icon, color: preset.color)
                        } label: {
                            HStack(spacing: 12) {
                                MedicineIconBadge(iconName: preset.icon, colorHex: preset.color, size: 30)
                                Text(preset.name).foregroundStyle(.primary)
                                Spacer()
                                Text(preset.kind == .symptom ? "0–10" : (preset.unit ?? "number"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    TextField("Name (e.g. Headache, Steps)", text: $name)
                        .textInputAutocapitalization(.sentences)
                    Picker("Type", selection: $kind) {
                        Text("Symptom (0–10)").tag(MetricKind.symptom)
                        Text("Vital (number)").tag(MetricKind.vital)
                    }
                    if kind == .vital {
                        TextField("Unit (e.g. kg, mmHg)", text: $unit)
                            .textInputAutocapitalization(.never)
                    }
                    Button("Add") {
                        create(name: name, kind: kind, valueKind: kind == .symptom ? .severity : .number,
                               unit: kind == .vital ? unit : nil, icon: kind == .symptom ? "waveform.path.ecg" : "chart.dots.scatter",
                               color: "#0A84FF")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Or create your own")
                }
            }
            .navigationTitle("Track something")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Couldn't save", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: { Text("Please try again.") }
        }
    }

    private func create(name: String, kind: MetricKind, valueKind: MetricValueKind,
                        unit: String?, icon: String, color: String) {
        do {
            try MetricWriter.createMetric(name: name, kind: kind, valueKind: valueKind, unit: unit,
                                          iconName: icon, colorHex: color, into: context, existing: metrics)
            Haptics.light()
            dismiss()
        } catch {
            saveError = true
        }
    }
}
