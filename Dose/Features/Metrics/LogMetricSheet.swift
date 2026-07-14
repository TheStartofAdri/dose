import SwiftUI
import SwiftData

/// Log one measurement for a metric: a 0–10 severity slider for symptoms, or a number + unit for vitals.
/// Prefills with the most recent entry ("same as last time") and shows recent history for context.
struct LogMetricSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let metric: TrackedMetric

    @State private var severity: Double = 5
    @State private var valueText = ""
    @State private var note = ""
    @State private var saveError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if metric.valueKind == .severity {
                        VStack(spacing: 8) {
                            Text("\(Int(severity))")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(MedAppearance.color(metric.colorHex))
                                .accessibilityLabel("Severity \(Int(severity)) of 10")
                            Slider(value: $severity, in: 0...10, step: 1) {
                                Text("Severity")
                            } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("10") }
                            HStack { Text("None"); Spacer(); Text("Severe") }
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        HStack {
                            TextField("Value", text: $valueText)
                                .keyboardType(.decimalPad)
                                .font(.title2.weight(.semibold))
                            if let unit = metric.unit, !unit.isEmpty {
                                Text(unit).foregroundStyle(.secondary)
                            }
                        }
                    }
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Log \(metric.name)")
                }

                let recent = metric.recentEntries(limit: 8)
                if !recent.isEmpty {
                    Section("Recent") {
                        ForEach(recent, id: \.id) { entry in
                            HStack(spacing: 8) {
                                Text(entry.displayValue).font(.subheadline.weight(.medium))
                                if let n = entry.note { Text(n).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                Spacer(minLength: 0)
                                Text(entry.loggedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(metric.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
            .onAppear(perform: prefill)
            .alert("Couldn't save", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: { Text("Please try again.") }
        }
    }

    private var parsedValue: Double? { Double(valueText.replacingOccurrences(of: ",", with: ".")) }
    private var canSave: Bool { metric.valueKind == .severity || parsedValue != nil }

    /// "Same as last time" — prefill the input with the most recent entry.
    private func prefill() {
        guard let last = metric.latestEntry else { return }
        if let s = last.severity { severity = Double(s) }
        if let v = last.value { valueText = v == v.rounded() ? String(Int(v)) : String(v) }
    }

    private func save() {
        do {
            if metric.valueKind == .severity {
                try MetricWriter.log(metric, severity: Int(severity), note: note, into: context)
            } else if let v = parsedValue {
                try MetricWriter.log(metric, value: v, note: note, into: context)
            } else { return }
            Haptics.success()
            dismiss()
        } catch {
            saveError = true
        }
    }
}
