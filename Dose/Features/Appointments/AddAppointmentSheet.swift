import SwiftUI
import SwiftData

/// Create or edit an `Appointment`. Only a title + date are required; provider, location, duration,
/// a reminder lead-time, and notes are optional. Wellness framing — a memory aid for care visits.
struct AddAppointmentSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil = creating a new appointment; non-nil = editing that one.
    let editing: Appointment?

    @State private var title = ""
    @State private var provider = ""
    @State private var location = ""
    @State private var startsAt = AddAppointmentSheet.defaultStart()
    @State private var durationMinutes: Int? = nil
    @State private var reminderLead: Int? = 1440       // default: the day before
    @State private var notes = ""
    @State private var saveError = false

    init(editing: Appointment? = nil) { self.editing = editing }

    /// (label, minutes-before-start). nil = no reminder.
    private let reminderOptions: [(String, Int?)] = [
        ("No reminder", nil), ("At the time", 0), ("1 hour before", 60), ("3 hours before", 180),
        ("The day before", 1440), ("2 days before", 2880), ("1 week before", 10080),
    ]
    /// (label, minutes). nil = unspecified.
    private let durationOptions: [(String, Int?)] = [
        ("Not set", nil), ("15 min", 15), ("30 min", 30), ("45 min", 45), ("1 hour", 60), ("1.5 hours", 90),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (e.g. Cardiology follow-up)", text: $title)
                        .textInputAutocapitalization(.sentences)
                    TextField("Provider (e.g. Dr. Smith)", text: $provider)
                        .textInputAutocapitalization(.words)
                    TextField("Location (optional)", text: $location)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    DatePicker("Date & time", selection: $startsAt)
                    Picker("Duration", selection: durationBinding) {
                        ForEach(durationOptions, id: \.0) { Text($0.0).tag($0.1) }
                    }
                }

                Section {
                    Picker("Remind me", selection: reminderBinding) {
                        ForEach(reminderOptions, id: \.0) { Text($0.0).tag($0.1) }
                    }
                } footer: {
                    Text("A reminder is a memory aid for your visit. Dose doesn't provide medical advice.")
                }

                Section("Notes") {
                    TextField("Questions to ask, things to bring…", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .textInputAutocapitalization(.sentences)
                }
            }
            .navigationTitle(editing == nil ? "New appointment" : "Edit appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
            .onAppear(perform: prefill)
            .alert("Couldn't save", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: { Text("Please try again.") }
        }
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    // Picker tags are optionals; these bindings keep the `Int?` selection type explicit.
    private var durationBinding: Binding<Int?> { Binding(get: { durationMinutes }, set: { durationMinutes = $0 }) }
    private var reminderBinding: Binding<Int?> { Binding(get: { reminderLead }, set: { reminderLead = $0 }) }

    /// The next round half-hour from now, as a sensible default start time.
    private static func defaultStart() -> Date {
        let cal = Calendar.current
        let base = cal.date(byAdding: .hour, value: 1, to: .now) ?? .now
        let minute = cal.component(.minute, from: base)
        let rounded = cal.date(bySetting: .minute, value: minute < 30 ? 30 : 0, of: base) ?? base
        // If we rounded 30→00 it may have stayed in the same hour; nudge to the next hour when needed.
        return rounded > .now ? rounded : cal.date(byAdding: .minute, value: 30, to: rounded) ?? rounded
    }

    private func prefill() {
        guard let appt = editing else { return }
        title = appt.title
        provider = appt.providerName ?? ""
        location = appt.location ?? ""
        startsAt = appt.startsAt
        durationMinutes = appt.durationMinutes
        reminderLead = appt.reminderLeadMinutes
        notes = appt.notes ?? ""
    }

    private func save() {
        do {
            if let appt = editing {
                try AppointmentWriter.update(appt, title: title, providerName: provider, location: location,
                                             startsAt: startsAt, durationMinutes: durationMinutes,
                                             notes: notes, reminderLeadMinutes: reminderLead, into: context)
            } else {
                try AppointmentWriter.create(title: title, providerName: provider, location: location,
                                             startsAt: startsAt, durationMinutes: durationMinutes,
                                             notes: notes, reminderLeadMinutes: reminderLead, into: context)
            }
            Haptics.success()
            dismiss()
        } catch {
            saveError = true
        }
    }
}
