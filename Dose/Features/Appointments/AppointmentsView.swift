import SwiftUI
import SwiftData

/// The appointments surface — reached from Today. Upcoming visits (soonest first) with their reminder,
/// plus a collapsed-feeling Past section for reference. A `+` adds one; tap a row to edit, swipe to delete.
struct AppointmentsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Appointment.startsAt) private var appointments: [Appointment]

    @State private var showAdd = false
    @State private var editing: Appointment?

    var body: some View {
        NavigationStack {
            Group {
                if appointments.isEmpty {
                    VStack {
                        Spacer()
                        DoseEmptyState(icon: "calendar",
                                       title: "No appointments",
                                       message: "Keep track of doctor visits and check-ups — with a reminder so one never slips.") {
                            Button { showAdd = true } label: { Label("Add appointment", systemImage: "plus") }
                                .buttonStyle(.borderedProminent)
                        }
                        Spacer()
                    }
                } else {
                    // TimelineView drives `now` (so relative times refresh) but wraps the List — the
                    // ForEach + `.onDelete` stay DIRECT List-section children, so swipe-to-delete and
                    // grouped section headers render natively (nesting them under TimelineView broke that).
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        let now = timeline.date
                        let upcoming = Appointment.upcoming(appointments, now: now)
                        let past = Appointment.past(appointments, now: now)
                        List {
                            Section("Upcoming") {
                                if upcoming.isEmpty {
                                    Text("Nothing scheduled").foregroundStyle(.secondary)
                                } else {
                                    ForEach(upcoming) { row($0, now: now) }
                                        .onDelete { deleteFrom(upcoming, $0) }
                                }
                            }
                            if !past.isEmpty {
                                Section("Past") {
                                    ForEach(past) { row($0, now: now) }
                                        .onDelete { deleteFrom(past, $0) }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .navigationTitle("Appointments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add appointment")
                }
            }
            .sheet(isPresented: $showAdd) { AddAppointmentSheet() }
            .sheet(item: $editing) { AddAppointmentSheet(editing: $0) }
        }
    }

    private func row(_ appt: Appointment, now: Date) -> some View {
        Button { editing = appt } label: {
            HStack(spacing: 12) {
                MedicineIconBadge(iconName: appt.iconName ?? "calendar", colorHex: appt.colorHex, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(appt.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    if let subtitle = appt.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(appt.startsAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !appt.isPast(now: now) {
                    Text(appt.startsAt.formatted(.relative(presentation: .named)))
                        .font(.caption.weight(.medium)).foregroundStyle(DoseColors.accent)
                        .multilineTextAlignment(.trailing)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appt.title), \(appt.startsAt.formatted(date: .abbreviated, time: .shortened))")
        .accessibilityHint("Edit appointment")
    }

    private func deleteFrom(_ list: [Appointment], _ offsets: IndexSet) {
        for index in offsets { try? AppointmentWriter.delete(list[index], from: context) }
    }
}

/// The next upcoming appointment, as a compact tappable card for Today. Renders nothing when there's
/// none scheduled, so it never adds space for users who don't track appointments.
struct NextAppointmentCard: View {
    let appointment: Appointment
    var now: Date = .now
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                MedicineIconBadge(iconName: appointment.iconName ?? "calendar", colorHex: appointment.colorHex, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next appointment").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(appointment.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(appointment.startsAt.formatted(date: .abbreviated, time: .shortened)) · \(appointment.startsAt.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .doseCardStyle(padding: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next appointment: \(appointment.title), \(appointment.startsAt.formatted(.relative(presentation: .named)))")
    }
}
