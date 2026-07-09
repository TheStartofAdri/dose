import SwiftUI
import SwiftData

/// Notes: create / edit / delete, with tags, an optional linked medicine, and photo attachments (all
/// v6). Filterable by tag and searchable. A note can still be explicitly analyzed into a medicine
/// draft (in the editor) — always a manual, user-initiated action.
struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]
    @Query(sort: \Medicine.name) private var medicines: [Medicine]

    @State private var selectedNote: Note?
    @State private var search = ""
    @State private var tagFilter: NoteTag?

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    emptyState
                } else {
                    let shown = filtered
                    VStack(spacing: 0) {
                        filterChips
                        if shown.isEmpty {
                            Spacer()
                            DoseEmptyState(icon: "magnifyingglass", title: "No matching notes",
                                           message: "Try a different tag or search term.")
                            Spacer()
                        } else {
                            List {
                                ForEach(shown) { note in
                                    Button { selectedNote = note } label: { row(note) }
                                        .buttonStyle(.plain)
                                }
                                .onDelete { offsets in delete(shown, offsets) }
                            }
                            .listStyle(.plain)
                        }
                    }
                    .background(DoseColors.groupedBackground)
                }
            }
            .navigationTitle("Notes")
            .searchable(text: $search, prompt: "Search notes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { addNote() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add note")
                }
            }
            .navigationDestination(isPresented: selectionBinding) {
                if let note = selectedNote { NoteEditorView(note: note) }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No notes yet", systemImage: "note.text")
        } description: {
            Text("Jot anything down. You can analyze a note to draft a medicine — nothing is sent unless you choose to.")
        } actions: {
            Button { addNote() } label: { Label("New note", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DoseSpacing.sm) {
                FilterChip(title: "All", isSelected: tagFilter == nil) { tagFilter = nil }
                ForEach(NoteTag.allCases) { tag in
                    FilterChip(title: tag.rawValue, isSelected: tagFilter == tag) {
                        tagFilter = (tagFilter == tag) ? nil : tag
                    }
                }
            }
            .padding(.horizontal, DoseSpacing.lg)
            .padding(.vertical, DoseSpacing.sm)
        }
    }

    private var filtered: [Note] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return notes.filter { note in
            (tagFilter == nil || note.resolvedTags.contains(tagFilter!)) &&
            (q.isEmpty
                || note.text.lowercased().contains(q)
                || note.resolvedTags.contains { $0.rawValue.lowercased().contains(q) }
                || (medicineName(note)?.lowercased().contains(q) ?? false))
        }
    }

    private func row(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.text.isEmpty ? "New note" : note.text)
                .font(.body)
                .foregroundStyle(note.text.isEmpty ? .secondary : .primary)
                .lineLimit(2)
            if !note.resolvedTags.isEmpty { NoteTagChips(tags: note.resolvedTags) }
            HStack(spacing: DoseSpacing.md) {
                Text(note.createdAt, format: .dateTime.month().day().hour().minute())
                if let med = medicineName(note) {
                    Label(med, systemImage: "pills.fill")
                }
                if !note.photos.isEmpty {
                    Label("\(note.photos.count)", systemImage: "photo")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)   // whole-row tap target
        .contentShape(Rectangle())
    }

    private func medicineName(_ note: Note) -> String? {
        guard let id = note.medicineID else { return nil }
        return medicines.first { $0.id == id }?.name
    }

    private func addNote() {
        let note = Note(text: "")
        context.insert(note)
        try? context.save()
        selectedNote = note
    }

    private func delete(_ shown: [Note], _ offsets: IndexSet) {
        for index in offsets { context.delete(shown[index]) }
        try? context.save()
    }

    private var selectionBinding: Binding<Bool> {
        Binding(get: { selectedNote != nil }, set: { if !$0 { selectedNote = nil } })
    }
}
