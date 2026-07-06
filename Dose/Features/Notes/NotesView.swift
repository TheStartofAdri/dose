import SwiftUI
import SwiftData

/// Plain-text notes: create / edit / delete, stored locally like everything else. Deliberately
/// minimal — no symptom tracking, severity, categories, or trends. A note can be explicitly analyzed
/// into a medicine draft (in the editor), but that's always a manual, user-initiated action.
struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Note.createdAt, order: .reverse) private var notes: [Note]

    @State private var selectedNote: Note?

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    ContentUnavailableView {
                        Label("No notes yet", systemImage: "note.text")
                    } description: {
                        Text("Jot anything down. You can analyze a note to draft a medicine — nothing is sent unless you choose to.")
                    } actions: {
                        Button { addNote() } label: { Label("New note", systemImage: "plus") }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(notes) { note in
                            Button { selectedNote = note } label: { row(note) }
                                .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Notes")
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

    private func row(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.text.isEmpty ? "New note" : note.text)
                .font(.body)
                .foregroundStyle(note.text.isEmpty ? .secondary : .primary)
                .lineLimit(2)
            Text(note.createdAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)   // whole-row tap target
        .contentShape(Rectangle())
    }

    private func addNote() {
        let note = Note(text: "")
        context.insert(note)
        try? context.save()
        selectedNote = note
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(notes[index]) }
        try? context.save()
    }

    private var selectionBinding: Binding<Bool> {
        Binding(get: { selectedNote != nil }, set: { if !$0 { selectedNote = nil } })
    }
}
