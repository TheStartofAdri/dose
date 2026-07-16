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
                                        // Force every row separator to the leading edge. Without this a
                                        // row with trailing content (the photo count `Label`) insets its
                                        // separator to start AFTER that label — a stray mid-row line.
                                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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
        VStack {
            Spacer()
            DoseEmptyState(icon: "note.text",
                           title: "No notes yet",
                           message: "Jot anything down. You can analyze a note to draft a medicine — nothing is sent unless you choose to.") {
                Button { addNote() } label: { Label("New note", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
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
                if let med = linkedMedicine(note) {
                    HStack(spacing: 4) {
                        MedicineIconBadge(iconName: med.iconName, colorHex: med.colorHex, size: 16)
                        Text(med.name)
                    }
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

    private func linkedMedicine(_ note: Note) -> Medicine? {
        guard let id = note.medicineID else { return nil }
        return medicines.first { $0.id == id }
    }

    private func medicineName(_ note: Note) -> String? { linkedMedicine(note)?.name }

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
