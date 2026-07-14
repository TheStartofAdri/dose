import SwiftUI
import SwiftData

/// Choose which medicines and what date range, then generate the adherence PDF and hand it to the
/// share sheet. Premium-destined (reached only via the `Entitlements.isPremium` gate at the entry
/// points), and fully on-device.
struct ReportOptionsView: View {
    @Query(sort: \Medicine.name) private var medicines: [Medicine]   // filtered via `listed` (active + confirmed)
    @Query(sort: \DoseLog.scheduledFor) private var logs: [DoseLog]
    @Query(sort: \TrackedMetric.sortOrder) private var trackedMetrics: [TrackedMetric]
    @Query(sort: \Appointment.startsAt) private var appointments: [Appointment]

    /// Medicine IDs to start checked (e.g. a single med from its detail). `nil` = select all.
    var preselected: Set<UUID>?

    @State private var selected: Set<UUID> = []
    @State private var preset: RangePreset = .last7
    @State private var customFrom: Date = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @State private var customTo: Date = .now
    @State private var share: ShareableFile?

    enum RangePreset: String, CaseIterable, Identifiable {
        case last7 = "7 days", last30 = "30 days", custom = "Custom"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section("Medicines") {
                if listed.isEmpty {
                    Text("No medicines yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(listed) { med in
                        Button { toggle(med.id) } label: {
                            HStack(spacing: 12) {
                                MedicineIconBadge(iconName: med.iconName, colorHex: med.colorHex, size: 28)
                                Text(med.name).foregroundStyle(.primary)
                                Spacer()
                                if selected.contains(med.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("medRow.\(med.name)")
                    }
                }
            }

            Section("Date range") {
                Picker("Range", selection: $preset) {
                    ForEach(RangePreset.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if preset == .custom {
                    DatePicker("From", selection: $customFrom, in: ...customTo, displayedComponents: .date)
                    DatePicker("To", selection: $customTo, in: customFrom..., displayedComponents: .date)
                }
            }

            Section {
                Text("The report is generated on your device. It's shared only when you choose a destination.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Export report")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: generate) {
                Label("Generate report", systemImage: "doc.text").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("generateReport")
            .disabled(selected.isEmpty)
            .padding()
            .background(.bar)
        }
        .sheet(item: $share) { file in ShareSheet(items: [file.url]) }
        .onAppear {
            // Only ever select medicines that are actually listed (confirmed + active) — never an
            // archived/non-confirmed med, even if `preselected` named one.
            if selected.isEmpty {
                let listedIDs = Set(listed.map(\.id))
                selected = (preselected ?? listedIDs).intersection(listedIDs)
            }
        }
    }

    /// The medicines this screen may show/select — the SAME confirmed+active set as Today/History/This
    /// week (via `Medicine.activeConfirmed`), so the report can never offer a medicine Today wouldn't.
    private var listed: [Medicine] { Medicine.activeConfirmed(medicines) }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private var range: ReportRange {
        switch preset {
        case .last7: return .last7
        case .last30: return .last30
        case .custom: return .custom(from: customFrom, to: customTo)
        }
    }

    private func generate() {
        let meds = listed.filter { selected.contains($0.id) }.map { $0.snapshot() }
        // Include every tracked metric with data in the range — a doctor report wants the whole picture.
        let (from, to) = range.resolved()
        let metricInputs = TrackedMetric.active(trackedMetrics).compactMap { metric -> MetricReportInput? in
            let vals = metric.entries.filter { $0.loggedAt >= from && $0.loggedAt <= to }
                .sorted { $0.loggedAt < $1.loggedAt }.compactMap(\.chartValue)
            return vals.isEmpty ? nil : MetricReportInput(name: metric.name, unit: metric.unit, values: vals)
        }
        let data = ReportBuilder.build(medicines: meds, logs: logs.map { $0.snapshot() },
                                       range: range, metricInputs: metricInputs,
                                       appointments: appointments.map { $0.snapshot() })
        let pdf = ReportPDFRenderer.render(data)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Adherence Report.pdf")
        try? pdf.write(to: url)
        share = ShareableFile(url: url)
    }
}
