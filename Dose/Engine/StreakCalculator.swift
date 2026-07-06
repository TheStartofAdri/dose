import Foundation

/// Computes the consecutive-day "no missed dose" streak from logs.
///
/// Pinned semantics (see tests):
/// - **Today in progress doesn't break the streak.** A dose only counts against a day once its
///   grace window has fully elapsed relative to `now`; not-yet-due (or still-in-grace) doses today
///   are ignored.
/// - **A zero-scheduled-dose day is neutral** — it neither breaks the streak nor adds to the count;
///   the chain passes straight through it.
/// - **An explicit `.skipped` is neutral** (resolves the slot). Only a *computed past-grace
///   no-action miss* breaks the streak — a deliberate skip (e.g. the prescriber paused the med)
///   must not be punished like a forgotten dose.
enum StreakCalculator {
    static func currentStreak(
        medicines: [MedicineSnapshot],
        logs: [DoseLogSnapshot],
        now: Date,
        grace: TimeInterval = ExecutionEngine.defaultGrace,
        calendar: Calendar = .current,
        maxLookbackDays: Int = 400
    ) -> Int {
        var streak = 0
        var day = calendar.startOfDay(for: now)

        for _ in 0..<maxLookbackDays {
            let slots = scheduledSlots(on: day, medicines: medicines, calendar: calendar)
            if slots.isEmpty {
                // Neutral: pass through without breaking or incrementing.
                day = previousDay(day, calendar: calendar)
                continue
            }
            let dayHasMiss = slots.contains { slot in
                isMiss(medicineID: slot.medicineID, scheduledFor: slot.scheduledFor, logs: logs, now: now, grace: grace)
            }
            if dayHasMiss { break }
            streak += 1
            day = previousDay(day, calendar: calendar)
        }
        return streak
    }

    // MARK: - Helpers

    private static func scheduledSlots(
        on day: Date,
        medicines: [MedicineSnapshot],
        calendar: Calendar
    ) -> [(medicineID: UUID, scheduledFor: Date)] {
        var slots: [(medicineID: UUID, scheduledFor: Date)] = []
        for medicine in medicines {
            for rule in medicine.rules {
                guard let date = rule.scheduledDate(on: day, calendar: calendar) else { continue }
                // The SAME lifetime rule Today and adherence use: no slot before the med existed (incl. a
                // morning slot on the afternoon it was added — never actionable, so never a miss) or after
                // its course's inclusive end day (post-end days stay neutral, never breaking the streak).
                guard ExecutionEngine.isWithinLifetime(scheduledFor: date, createdAt: medicine.createdAt,
                                                       endDate: medicine.endDate, calendar: calendar) else { continue }
                slots.append((medicine.id, date))
            }
        }
        return slots
    }

    /// A slot is a miss only if it has no `.taken`/`.skipped` resolution AND its grace window has
    /// fully elapsed relative to `now` (so in-progress today never counts as missed).
    private static func isMiss(
        medicineID: UUID,
        scheduledFor: Date,
        logs: [DoseLogSnapshot],
        now: Date,
        grace: TimeInterval
    ) -> Bool {
        let resolved = logs.contains {
            $0.medicineID == medicineID
            && ExecutionEngine.sameSlot($0.scheduledFor, scheduledFor)
            && ($0.action == .taken || $0.action == .skipped)
        }
        if resolved { return false }
        return now > scheduledFor.addingTimeInterval(grace)
    }

    private static func previousDay(_ day: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -1, to: day) ?? day.addingTimeInterval(-86_400)
    }
}
