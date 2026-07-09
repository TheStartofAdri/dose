import SwiftUI
import SwiftData
import PhotosUI

/// Edit a single note — text, tags, a linked medicine, and photo attachments — and (explicitly)
/// analyze it into a medicine draft. Analysis reuses the exact existing pipeline: only this note's
/// text is sent (`.text`), through `MedicationParser`, into the existing `ReviewConfirmView` gate. It
/// only ever runs on the user's tap — never on save or in the background — and a medicine is created
/// only if the user confirms in review.
struct NoteEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var note: Note
    @Query(sort: \Medicine.name) private var medicines: [Medicine]

    private let parser: MedicationParser = MedicationParserFactory.make()

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photosLoading = 0
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var drafts: [EditableDraft] = []
    @State private var showReview = false
    @ObservedObject private var subscription = SubscriptionStore.shared   // re-render on entitlement change
    @State private var paywall: PremiumFeature?
    @AppStorage(SettingsKeys.aiConsentGiven) private var aiConsentGiven = false
    @State private var showAIConsent = false

    private var trimmed: String { note.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var activeMedicines: [Medicine] { Medicine.activeConfirmed(medicines) }

    /// Editor tags as a typed set, mapped back to the note's raw `[String]` in `NoteTag.allCases` order.
    private var tagsBinding: Binding<Set<NoteTag>> {
        Binding(
            get: { Set(note.resolvedTags) },
            set: { newValue in note.tags = NoteTag.allCases.filter(newValue.contains).map(\.rawValue) }
        )
    }
    private var medicineBinding: Binding<UUID?> {
        Binding(get: { note.medicineID }, set: { note.medicineID = $0 })
    }

    var body: some View {
        Form {
            Section("Note") {
                TextField("Write a note…", text: $note.text, axis: .vertical)
                    .lineLimit(5...20)
            }

            Section("Tags") {
                TagPicker(selected: tagsBinding)
            }

            Section("Medicine") {
                Picker("Linked medicine", selection: medicineBinding) {
                    Text("None").tag(UUID?.none)
                    ForEach(activeMedicines) { med in Text(med.name).tag(Optional(med.id)) }
                }
            }

            Section("Photos") {
                PhotoAttachmentRow(photos: note.photos, onDelete: deletePhoto)
                PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                    Label("Add photo", systemImage: "photo.badge.plus")
                }
                .accessibilityIdentifier("addPhoto")
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
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
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
    /// A note is discarded on exit only when it's truly empty — no text AND no tags/medicine/photos AND
    /// no photo load still in flight. A pending load must NOT be mistaken for "empty": it appends its
    /// `NotePhoto` asynchronously, so discarding here would delete the note out from under that append
    /// (silent photo loss / a write to a deleted model). Pure + static so it's unit-testable.
    static func shouldDiscard(trimmedText: String, hasTags: Bool, hasMedicine: Bool,
                              hasPhotos: Bool, photosLoading: Bool) -> Bool {
        trimmedText.isEmpty && !hasTags && !hasMedicine && !hasPhotos && !photosLoading
    }

    private func saveOrDiscard() {
        if Self.shouldDiscard(trimmedText: trimmed, hasTags: !note.tags.isEmpty,
                              hasMedicine: note.medicineID != nil, hasPhotos: !note.photos.isEmpty,
                              photosLoading: photosLoading > 0) {
            context.delete(note)            // truly-empty, no load pending → discard
        } else if note.text != trimmed {
            note.text = trimmed             // trim surrounding whitespace on save
        }
        try? context.save()
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photosLoading += 1                       // block discard-on-exit until this load resolves
        Task { @MainActor in                     // model-context writes stay on the main actor
            defer { photosLoading -= 1; photoItems = [] }
            for item in items {
                guard !note.isDeleted else { break }   // the note can be torn down mid-load — never
                if let data = try? await item.loadTransferable(type: Data.self), !note.isDeleted {
                    note.photos.append(NotePhoto(imageData: data))   // append to / save a deleted model
                }
            }
            if !note.isDeleted { try? context.save() }
        }
    }

    private func deletePhoto(_ photo: NotePhoto) {
        note.photos.removeAll { $0.id == photo.id }
        context.delete(photo)
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
