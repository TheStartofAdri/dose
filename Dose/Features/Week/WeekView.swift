import SwiftUI
import SwiftData

/// Read-only forward look at the next 7 days (today … today+6). A projection of the scheduling rules —
/// it shows medicine + scheduled time + dosage, grouped by day. NOT an execution screen: no
/// Take/Skip/Undo, no editing, no week navigation. Taking doses still happens only on Today.
///
/// Occurrences come from `ExecutionEngine.scheduledSlots(confirmedMedicines:on:)` — the SAME engine
/// Today uses — so the week view can never disagree with Today about what's scheduled when.
struct WeekView: View {
    @Query(sort: \Medicine.name) private var medicines: [Medicine]
    @State private var selectedMedicine: Medicine?

    private var days: [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        List {
            ForEach(days, id: \.self) { day in
                Section {
                    let slots = ExecutionEngine.scheduledSlots(confirmedMedicines: medicines, on: day)
                    if slots.isEmpty {
                        Text("Nothing scheduled")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(slots) { slot in
                            row(for: slot)
                        }
                    }
                } header: {
                    Text(header(for: day))
                }
            }
        }
        .navigationTitle("This week")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedMedicine) { medicine in
            MedicineDetailView(medicine: medicine)
        }
    }

    private func medicine(for slot: ScheduledSlot) -> Medicine? {
        medicines.first { $0.id == slot.medicineID }
    }

    /// A lightweight read-only row mirroring the Today card's icon badge + time + name + dosage. The
    /// whole row is tappable and opens the medicine's detail — the only interaction here.
    private func row(for slot: ScheduledSlot) -> some View {
        let med = medicine(for: slot)
        return Button {
            if let med { selectedMedicine = med }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: MedAppearance.icon(med?.iconName))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(MedAppearance.color(med?.colorHex), in: Circle())
                Text(slot.scheduledFor, format: .dateTime.hour().minute())
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.medicineName).font(.headline)
                    if let dosage = slot.dosage, !dosage.isEmpty {
                        Text(dosage).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func header(for day: Date) -> String {
        Calendar.current.isDateInToday(day)
            ? "Today"
            : day.formatted(.dateTime.weekday(.wide).month().day())
    }
}
