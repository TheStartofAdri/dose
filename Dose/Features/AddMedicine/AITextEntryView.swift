import SwiftUI

/// AI text entry (premium). Describe medicines in words; the edge function structures them; the
/// result flows into the review gate as drafts — never saved blindly.
struct AITextEntryView: View {
    private let parser: MedicationParser = MedicationParserFactory.make()

    @State private var text = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var drafts: [EditableDraft] = []
    @State private var goReview = false
    @AppStorage(SettingsKeys.aiConsentGiven) private var aiConsentGiven = false
    @State private var showAIConsent = false

    var body: some View {
        Group {
            if AppConfig.aiConfigured {
                form
            } else {
                NotConfiguredView()
            }
        }
        .navigationTitle("Describe")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goReview) {
            ReviewConfirmView(drafts: drafts)
        }
        .aiConsentGate(isPresented: $showAIConsent) { aiConsentGiven = true; generate() }
    }

    private var form: some View {
        Form {
            Section("What do you take?") {
                TextField(
                    "e.g. Vitamin D every morning and amoxicillin twice a day",
                    text: $text, axis: .vertical
                )
                .lineLimit(3...8)
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
            Section {
                Text("AI fills in the details — you'll review and confirm everything before it's saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: requestGenerate) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Generate").font(.headline).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            .padding()
            .background(.bar)
        }
    }

    /// First AI use shows the one-time consent; after that it parses directly.
    private func requestGenerate() {
        if aiConsentGiven { generate() } else { showAIConsent = true }
    }

    private func generate() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let parsed = try await parser.parse(.text(text))
                drafts = parsed.map { EditableDraft(from: $0, source: .ai) }
                isLoading = false
                if drafts.isEmpty {
                    errorMessage = "No medicines found. Try rephrasing, or add it manually."
                } else {
                    goReview = true
                }
            } catch {
                isLoading = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

/// Shown when Supabase/AI configuration is missing — keeps manual entry as the always-available path.
struct NotConfiguredView: View {
    var body: some View {
        ContentUnavailableView {
            Label("AI not set up", systemImage: "wifi.slash")
        } description: {
            Text("Add your Supabase configuration to use AI features. Manual entry always works offline.")
        }
    }
}
