import SwiftUI

/// Dismisses the entire Setup sheet from anywhere in the pushed navigation stack (the standard
/// `\.dismiss` only pops one level when called from a pushed view).
struct DismissFlowAction {
    let action: () -> Void
    func callAsFunction() { action() }
}

private struct DismissFlowKey: EnvironmentKey {
    static let defaultValue = DismissFlowAction(action: {})
}

extension EnvironmentValues {
    var dismissFlow: DismissFlowAction {
        get { self[DismissFlowKey.self] }
        set { self[DismissFlowKey.self] = newValue }
    }
}

/// Entry point for Setup Mode, presented as a sheet. New medicines start at the method chooser;
/// editing jumps straight to the manual form (the user's own data — no AI, no review gate).
struct AddMedicineFlow: View {
    @Environment(\.dismiss) private var dismiss
    var editing: Medicine?

    var body: some View {
        NavigationStack {
            Group {
                if let editing {
                    ManualEntryView(editing: editing)
                } else {
                    MethodChooserView()
                }
            }
        }
        .environment(\.dismissFlow, DismissFlowAction { dismiss() })
    }
}

/// The three ways to add a medicine. Manual is always free and offline; AI text and Scan are
/// premium and live in Setup Mode only.
struct MethodChooserView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.aiEnabled) private var aiEnabled = true
    @ObservedObject private var subscription = SubscriptionStore.shared   // re-render on entitlement change
    @State private var paywall: PremiumFeature?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ManualEntryView()
                } label: {
                    MethodRow(title: "Manual entry", subtitle: "Free · works offline",
                              systemImage: "square.and.pencil", tint: .blue)
                }
            }
            // AI text + scan are premium. Subscribers (with AI on) get the live links; everyone else sees
            // the rows with a "Premium" badge that opens the unlock paywall (manual entry stays free).
            if Entitlements.isPremium && aiEnabled {
                Section("Faster with AI") {
                    NavigationLink {
                        AITextEntryView()
                    } label: {
                        MethodRow(title: "Describe in words", subtitle: "“Vitamin D every morning…”",
                                  systemImage: "text.bubble", tint: .purple)
                    }
                    NavigationLink {
                        ScanLabelView()
                    } label: {
                        MethodRow(title: "Scan label", subtitle: "Works best in English",
                                  systemImage: "camera.viewfinder", tint: .pink)
                    }
                }
            } else if !Entitlements.isPremium {
                Section("Faster with AI") {
                    Button { paywall = .aiTextEntry } label: {
                        MethodRow(title: "Describe in words", subtitle: "Premium · tap to unlock",
                                  systemImage: "text.bubble", tint: .purple)
                    }
                    .buttonStyle(.plain)
                    Button { paywall = .scanLabel } label: {
                        MethodRow(title: "Scan label", subtitle: "Premium · tap to unlock",
                                  systemImage: "camera.viewfinder", tint: .pink)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Add medicine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(item: $paywall) { PaywallView(context: .unlock($0)) }
    }
}

private struct MethodRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
