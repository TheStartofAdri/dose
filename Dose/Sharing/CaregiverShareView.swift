import SwiftUI
import SwiftData

/// Phase 1: the in-app "Share with a caregiver" flow. Premium-gated at the Settings entry point and
/// consent-gated here — this is the first place Dose data leaves the device, so the user explicitly
/// confirms what's shared before a link is created. Read-only, revocable, HealthKit values excluded.
struct CaregiverShareView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Medicine.name) private var medicines: [Medicine]
    @Query(sort: \DoseLog.scheduledFor) private var logs: [DoseLog]
    @Query(sort: \Appointment.startsAt) private var appointments: [Appointment]
    @Query(sort: \TrackedMetric.sortOrder) private var trackedMetrics: [TrackedMetric]

    @State private var active = CaregiverShareStore.active()
    @State private var showConsent = false
    @State private var working = false
    @State private var copied = false
    @State private var errorMessage: String?
    @State private var shareItem: ShareableFile?

    private var isConfigured: Bool { AppConfig.caregiverShareEndpoint != nil }

    var body: some View {
        NavigationStack {
            Form {
                if !isConfigured {
                    Section {
                        Label("Caregiver sharing isn't available in this build yet.", systemImage: "wifi.slash")
                            .foregroundStyle(.secondary)
                    }
                } else if let share = active {
                    activeSection(share)
                } else {
                    createSection
                }

                Section {
                    Text("A caregiver sees a read-only summary: adherence, upcoming appointments, and recent symptoms/vitals. It never includes data synced from Apple Health, and it's not medical advice. You can stop sharing at any time.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Share with a caregiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
            .sheet(isPresented: $showConsent) { consentSheet }
            .alert("Couldn't do that", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "Please try again.") }
            // A full-bleed, hit-testing dimmed scrim so the form can't be tapped mid-request (a
            // half-completed create/revoke otherwise stays interactive). Announces itself to VoiceOver.
            .overlay {
                if working {
                    ZStack {
                        Color.black.opacity(0.12).ignoresSafeArea()
                        ProgressView()
                            .controlSize(.large)
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Working…")
                }
            }
            // Re-read the active share each time the sheet appears (it may have expired since last open).
            .onAppear { active = CaregiverShareStore.active() }
        }
    }

    // MARK: - No active share

    private var createSection: some View {
        Section {
            Button {
                showConsent = true
            } label: {
                Label("Create a share link", systemImage: "link.badge.plus")
            }
            .disabled(working)
        } header: {
            Text("Not sharing")
        } footer: {
            Text("Creates a private link you can send to a trusted caregiver. The link expires automatically after 7 days; refresh or revoke it any time.")
        }
    }

    // MARK: - Active share

    private func activeSection(_ share: CaregiverShareResult) -> some View {
        Section {
            HStack {
                Label("Link active", systemImage: "checkmark.circle.fill").foregroundStyle(DoseColors.taken)
                Spacer()
                Text("until \(share.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                shareItem = ShareableFile(url: share.viewUrl)
            } label: { Label("Send link", systemImage: "square.and.arrow.up") }
            .disabled(working)

            Button {
                UIPasteboard.general.url = share.viewUrl
                Haptics.light()
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            } label: {
                Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? DoseColors.taken : DoseColors.accent)
            }
            .disabled(working)
            .animation(.default, value: copied)

            Button(role: .destructive) {
                Task { await revoke(share) }
            } label: { Label("Stop sharing", systemImage: "xmark.circle") }
            .disabled(working)
        } header: {
            Text("Sharing")
        } footer: {
            Text("The caregiver sees your latest summary when they open the link. Stop sharing to revoke it immediately.")
        }
    }

    // MARK: - Consent

    private var consentSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Before you share")
                        .font(.title2.weight(.bold))
                    consentRow("eye", "Read-only", "The caregiver can view your summary but can't change anything.")
                    consentRow("heart.slash", "No Apple Health data", "Values synced from Apple Health are never included.")
                    consentRow("icloud.and.arrow.up", "Leaves your device", "A minimized summary is stored on Dose's server behind a private link, so the caregiver can open it.")
                    consentRow("xmark.circle", "Revocable", "Stop sharing at any time and the link stops working. It also expires automatically after 7 days.")
                    Text("This isn't a medical record and isn't medical advice.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Share with a caregiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showConsent = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create link") { showConsent = false; Task { await create() } }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func consentRow(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(DoseColors.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func create() async {
        working = true; defer { working = false }
        do {
            let result = try await CaregiverShareClient().createShare(buildSnapshot())
            CaregiverShareStore.current = result
            active = result
            Haptics.success()
        } catch {
            errorMessage = friendly(error)
        }
    }

    private func revoke(_ share: CaregiverShareResult) async {
        working = true; defer { working = false }
        do {
            try await CaregiverShareClient().revoke(token: share.token)
            CaregiverShareStore.clear()
            active = nil
            Haptics.light()
        } catch {
            errorMessage = friendly(error)
        }
    }

    /// Build the minimized share payload from live data, excluding HealthKit-sourced metric values.
    private func buildSnapshot() -> CaregiverShareSnapshot {
        let meds = Medicine.activeConfirmed(medicines).map { $0.snapshot() }
        let entries = TrackedMetric.active(trackedMetrics).flatMap { metric in
            metric.entries.compactMap { e -> CaregiverShareBuilder.MetricEntryInput? in
                guard let value = e.chartValue else { return nil }
                return .init(name: metric.name, unit: metric.unit, value: value,
                             loggedAt: e.loggedAt, isHealthKit: e.source == .healthKit)
            }
        }
        return CaregiverShareBuilder.build(medicines: meds, logs: logs.map { $0.snapshot() },
                                           appointments: appointments.map { $0.snapshot() },
                                           metricEntries: entries)
    }

    private func friendly(_ error: Error) -> String {
        switch error as? CaregiverShareError {
        case .notConfigured: return "Caregiver sharing isn't set up yet."
        case .network: return "Couldn't reach the server. Check your connection and try again."
        case .server, .decoding, .none: return "Something went wrong. Please try again."
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
