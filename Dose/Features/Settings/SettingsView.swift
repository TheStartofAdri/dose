import SwiftUI
import SwiftData
import StoreKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var medicines: [Medicine]
    @Query private var logs: [DoseLog]

    @AppStorage(SettingsKeys.soundEnabled) private var soundEnabled = true
    @AppStorage(SettingsKeys.escalationEnabled) private var escalationEnabled = false
    @AppStorage(SettingsKeys.aiEnabled) private var aiEnabled = true
    @AppStorage(SettingsKeys.appearance) private var appearance = "system"
    @AppStorage(SettingsKeys.aiConsentGiven) private var aiConsentGiven = false

    @ObservedObject private var subscription = SubscriptionStore.shared
    @State private var showPaywall = false
    @State private var manageSubscriptions = false

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
                    Text("AI")
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
            .manageSubscriptionsSheet(isPresented: $manageSubscriptions)
        }
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
        NotificationScheduler.shared.reschedule(medicines: medicines, logs: logs, escalationEnabled: escalationEnabled)
    }
}
