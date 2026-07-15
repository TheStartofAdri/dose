import SwiftUI
import SwiftData
import StoreKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var medicines: [Medicine]
    @Query private var logs: [DoseLog]
    @Query private var notes: [Note]
    @Query private var trackedMetrics: [TrackedMetric]
    @Query private var appointments: [Appointment]

    @AppStorage(SettingsKeys.soundEnabled) private var soundEnabled = true
    @AppStorage(SettingsKeys.escalationEnabled) private var escalationEnabled = false
    @AppStorage(SettingsKeys.aiEnabled) private var aiEnabled = true
    @AppStorage(SettingsKeys.appearance) private var appearance = "system"
    @AppStorage(SettingsKeys.aiConsentGiven) private var aiConsentGiven = false

    @ObservedObject private var subscription = SubscriptionStore.shared
    @State private var showPaywall = false
    @State private var showReport = false
    @State private var showCaregiverShare = false
    @State private var manageSubscriptions = false
    @State private var shareFile: ShareableFile?
    @State private var confirmDeleteAll = false
    @State private var healthStatus: String?
    @State private var healthConnecting = false

    // Diagnostics: the startup reachability probe flips this when the AI backend host can't be reached.
    private let aiBackendHealth = AIBackendHealth.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if NotificationStatus.shared.hasNotice {
                        NotificationNoticeBanner(style: .plain)
                    }
                    Toggle("Reminder sound", isOn: $soundEnabled)
                        .onChange(of: soundEnabled) { reschedule() }
                    Toggle("Repeat reminder after 10 min", isOn: $escalationEnabled)
                        .onChange(of: escalationEnabled) { reschedule() }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Reminders are delivered as Time Sensitive, so they come through Focus and Do Not Disturb. “Repeat reminder after 10 min” sends one more reminder if you haven’t taken or skipped the dose.")
                }

                Section {
                    if subscription.isPremium {
                        Label("Subscription active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Manage subscription") { manageSubscriptions = true }
                    } else if subscription.hasEverSubscribed {
                        Label("Subscription lapsed", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Button("Resubscribe") { showPaywall = true }
                    } else {
                        Button("Start 7-day free trial") { showPaywall = true }
                    }
                    Button("Restore Purchases") { Task { await subscription.restore() } }
                } header: {
                    Text("Subscription")
                } footer: {
                    Text("Your reminders, history, and notes keep working even if your subscription lapses. Premium unlocks reports, AI add, scanning, and the weekly view.")
                }

                Section("Data & Reports") {
                    Button {
                        if Entitlements.isPremium { showReport = true } else { showPaywall = true }
                    } label: {
                        HStack {
                            Label("Export PDF report", systemImage: "square.and.arrow.up")
                                .foregroundStyle(.primary)
                            Spacer()
                            PROBadge()
                        }
                    }
                    .accessibilityIdentifier("exportReportRow")

                    Button {
                        exportAllData()
                    } label: {
                        Label("Export all my data (JSON)", systemImage: "arrow.down.doc")
                            .foregroundStyle(.primary)
                    }
                    .accessibilityIdentifier("exportDataRow")

                    Button {
                        if Entitlements.isPremium { showCaregiverShare = true } else { showPaywall = true }
                    } label: {
                        HStack {
                            Label("Share with a caregiver", systemImage: "person.2")
                                .foregroundStyle(.primary)
                            Spacer()
                            PROBadge()
                        }
                    }
                    .accessibilityIdentifier("caregiverShareRow")
                }

                Section {
                    Button(role: .destructive) { confirmDeleteAll = true } label: {
                        Label("Delete all my data", systemImage: "trash")
                    }
                    .accessibilityIdentifier("deleteAllRow")
                } footer: {
                    Text("Permanently removes every medicine, dose record, and note from this device. This can't be undone.")
                }

                // Shown only when there are archived medicines — the one place to restore or delete them.
                if !Medicine.archived(medicines).isEmpty {
                    Section("Medicines") {
                        NavigationLink {
                            ArchivedMedicinesView()
                        } label: {
                            LabeledContent("Archived medicines", value: "\(Medicine.archived(medicines).count)")
                        }
                    }
                }

                Section {
                    if HealthKitService.isAvailable {
                        Button {
                            Task { await connectHealth() }
                        } label: {
                            HStack {
                                Label("Connect Apple Health", systemImage: "heart.fill")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if healthConnecting { ProgressView() }
                            }
                        }
                        .disabled(healthConnecting)
                        .accessibilityIdentifier("connectHealthRow")
                        if let healthStatus {
                            Text(healthStatus).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Apple Health isn't available on this device.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Import vitals (weight, heart rate, glucose, oxygen) so you don't type them in, and save the vitals you log back to Health. Add a matching metric on the Track screen first.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }

                Section {
                    // Diagnostics: surfaced at launch by the reachability probe (or the DEBUG stub) when
                    // the AI backend host can't be reached (DNS/offline). Hidden when the backend is healthy.
                    if aiBackendHealth.isUnreachable {
                        aiBackendUnreachableBanner
                    }
                    Toggle("AI features", isOn: $aiEnabled)
                    // Shown only once the user has granted AI consent (via the in-flow prompt). Revoking
                    // resets the same flag the `.aiConsentGate` reads, so the prompt reappears next time.
                    if aiConsentGiven {
                        Button("Reset AI permission") { aiConsentGiven = false }
                            .accessibilityIdentifier("revokeAIConsent")
                    }
                } header: {
                    HStack { Text("AI"); PROBadge() }
                } footer: {
                    Text(aiSectionFooter)
                }

                Section {
                    Label("Scanning works best with English labels.", systemImage: "camera.viewfinder")
                        .font(.callout)
                } header: {
                    Text("Scanning")
                } footer: {
                    Text("Other languages may not read correctly — you can always edit or type the name after scanning. You review every result before it's saved.")
                }

                Section("Privacy") {
                    Label("Your medication list stays on your device. Only the text you choose to send is processed to fill in details.",
                          systemImage: "lock.fill")
                        .font(.callout)
                }

                // The privacy policy used to be reachable only from the paywall; surface it here too so a
                // non-subscriber can always find it (App Review expects it easily accessible). Both links use
                // the shared LegalLinks constants — the same source of truth the paywall's disclosure links use.
                Section("About") {
                    Link(destination: LegalLinks.privacy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    .accessibilityIdentifier("privacyPolicyLink")
                    Link(destination: LegalLinks.terms) {
                        Label("Terms of Use", systemImage: "doc.text")
                    }
                    .accessibilityIdentifier("termsOfUseLink")
                }

                Section {
                    Text("Dose is a reminder and habit tracker — not medical advice. AI suggestions are best-effort; if anything conflicts with the label or your prescriber, follow your prescriber.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) { PaywallView(context: .upgrade) }
            .sheet(isPresented: $showCaregiverShare) { CaregiverShareView() }
            .sheet(isPresented: $showReport) {
                NavigationStack { ReportOptionsView(preselected: nil) }
            }
            .sheet(item: $shareFile) { file in ShareSheet(items: [file.url]) }
            .confirmationDialog("Delete all data?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { deleteAllData() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes every medicine, dose record, and note from this device.")
            }
            .manageSubscriptionsSheet(isPresented: $manageSubscriptions)
        }
    }

    /// Export the full local dataset as a JSON file, then hand it to the system share sheet — nothing
    /// leaves the device unless the user chooses a destination.
    private func exportAllData() {
        guard let url = try? DataExport.writeTempFile(medicines: medicines, logs: logs, notes: notes,
                                                      metrics: trackedMetrics, appointments: appointments) else { return }
        shareFile = ShareableFile(url: url)
    }

    /// The user's delete right: clear every model and cancel all reminders.
    private func deleteAllData() {
        try? context.delete(model: DoseLog.self)
        try? context.delete(model: Note.self)        // cascades NotePhoto
        try? context.delete(model: NotePhoto.self)
        try? context.delete(model: DoseTime.self)
        try? context.delete(model: Medicine.self)    // cascades any remaining DoseTime
        try? context.delete(model: MetricEntry.self)
        try? context.delete(model: TrackedMetric.self)
        try? context.delete(model: Appointment.self)
        try? context.save()
        NotificationScheduler.shared.reschedule(medicines: [], logs: [], appointments: [], escalationEnabled: escalationEnabled)
        // The delete right must reach the OFF-DEVICE copy too: revoke any caregiver share on the server
        // and clear the local token, so a deleted user's summary stops being served (not left until its
        // 7-day TTL). Best-effort — a network failure still clears locally.
        if let share = CaregiverShareStore.current {
            Task { try? await CaregiverShareClient().revoke(token: share.token) }
            CaregiverShareStore.clear()
        }
        Haptics.light()
    }

    /// AI section footer — when consent is granted, explains what "Reset AI permission" does; otherwise
    /// the standard configured/not-configured copy.
    private var aiSectionFooter: String {
        if aiConsentGiven {
            return "You've allowed AI to read the text or photo you submit. “Reset AI permission” makes the app ask again before the next AI scan or text analysis. Every result is still reviewed before it's saved."
        }
        return AppConfig.aiConfigured
            ? "AI text and label scanning help you add medicines faster. Every result is reviewed before it's saved."
            : "AI text and label scanning require backend setup. Manual entry always works offline."
    }

    /// Inline notice shown when the startup probe found the AI backend unreachable (DNS/offline). Mirrors
    /// NotificationNoticeBanner's plain (in-Form) style and reassures that the core app is unaffected.
    private var aiBackendUnreachableBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI features are unavailable").font(.subheadline.weight(.semibold))
                Text("Our AI server couldn't be reached. Reminders and tracking work normally — you can still add medicines manually.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("aiBackendUnreachableNotice")
    }

    private func reschedule() {
        NotificationScheduler.shared.reschedule(medicines: medicines, logs: logs, appointments: appointments,
                                                escalationEnabled: escalationEnabled)
    }

    /// Request Health authorization for the HK-backed tracked metrics, then import recent vitals.
    private func connectHealth() async {
        healthConnecting = true
        defer { healthConnecting = false }
        let active = TrackedMetric.active(trackedMetrics)
        guard HealthKitService.shared.hasSyncableMetrics(active) else {
            healthStatus = "Add a vital like Weight, Heart rate, Glucose, or Oxygen on the Track screen first."
            return
        }
        guard await HealthKitService.shared.requestAuthorization(for: active) else {
            healthStatus = "Couldn't connect to Health."
            return
        }
        let n = await HealthKitService.shared.importRecent(for: active, into: context)
        healthStatus = n > 0 ? "Imported \(n) reading\(n == 1 ? "" : "s") from Health." : "Connected. No new readings to import."
    }
}
