import SwiftUI
import SwiftData

/// Edit a single note, and (explicitly) analyze it into a medicine draft. Analysis reuses the exact
/// existing pipeline: only this note's text is sent (`.text`), through `MedicationParser`, into the
/// existing `ReviewConfirmView` gate. It only ever runs on the user's tap — never on save or in the
/// background — and a medicine is created only if the user confirms in review.
struct NoteEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var note: Note

    private let parser: MedicationParser = MedicationParserFactory.make()

    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var drafts: [EditableDraft] = []
    @State private var showReview = false
    @ObservedObject private var subscription = SubscriptionStore.shared   // re-render on entitlement change
    @State private var paywall: PremiumFeature?
    @AppStorage(SettingsKeys.aiConsentGiven) private var aiConsentGiven = false
    @State private var showAIConsent = false

    private var trimmed: String { note.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section("Note") {
                TextField("Write a note…", text: $note.text, axis: .vertical)
                    .lineLimit(5...20)
            }

            if AppConfig.aiConfigured {
                Section {
                    Button(action: requestAnalyze) {
                        if isAnalyzing {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label(Entitlements.isPremium ? "Analyze → add as medicine"
                                                         : "Analyze → add as medicine (Premium)",
                                  systemImage: Entitlements.isPremium ? "wand.and.stars" : "lock.fill")
                        }
                    }
                    .accessibilityIdentifier("analyzeNote")
                    .disabled(trimmed.isEmpty || isAnalyzing)
                } footer: {
                    Text(Entitlements.isPremium
                         ? "Sends only this note's text to draft a medicine. You'll review and confirm before anything is saved — nothing happens automatically."
                         : "Premium feature. Turns this note into a medicine draft you review before saving — your notes and reminders stay free.")
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).font(.callout)
                }
            }
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Saving the note is the PRIMARY action — write and exit, no analysis.
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        // Back-navigation is non-destructive (keeps what was typed); blank notes don't linger.
        .onDisappear { saveOrDiscard() }
        .sheet(isPresented: $showReview) {
            NavigationStack {
                ReviewConfirmView(drafts: drafts)
            }
            .environment(\.dismissFlow, DismissFlowAction { showReview = false })
            .environment(\.modelContext, context)   // ensure the review writes to the shared store
        }
        .sheet(item: $paywall) { PaywallView(context: .unlock($0)) }
        .aiConsentGate(isPresented: $showAIConsent) { aiConsentGiven = true; analyze() }
    }

    /// Persist the note on exit, or remove it if the user left it blank (notes are inserted up front
    /// when "+" is tapped, so an empty-and-back shouldn't leave a stray row). Never analyzes.
    private func saveOrDiscard() {
        if trimmed.isEmpty {
            context.delete(note)            // never persist a blank/whitespace-only note
        } else if note.text != trimmed {
            note.text = trimmed             // trim surrounding whitespace on save
        }
        try? context.save()
    }

    /// Gate order: premium first (note-analyze hits the same paid parser as AI add / scan, so a
    /// non-subscriber goes to the paywall), then the one-time AI consent, then parse.
    private func requestAnalyze() {
        guard Entitlements.isPremium else { paywall = .aiTextEntry; return }
        if aiConsentGiven { analyze() } else { showAIConsent = true }
    }

    private func analyze() {
        isAnalyzing = true
        errorMessage = nil
        let text = note.text            // capture: only this note's text is ever sent
        Task {
            do {
                let parsed = try await parser.parse(NoteAnalysis.parserInput(for: text))
                drafts = parsed.map { EditableDraft(from: $0, source: .ai) }
                isAnalyzing = false
                if drafts.isEmpty {
                    errorMessage = "No medicine found in this note. Try rephrasing, or add it manually."
                } else {
                    showReview = true   // mandatory review; never auto-saved
                }
            } catch {
                isAnalyzing = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
