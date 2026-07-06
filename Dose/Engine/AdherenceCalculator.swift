import Foundation

/// Per-day adherence, computed from logs. Behavioural, not medical.
///
/// A scheduled slot resolves to exactly one of:
/// - `taken`   — a `.taken` log exists (adherence numerator AND denominator),
/// - `skipped` — a `.skipped` log exists (NEUTRAL: out of both numerator and denominator),
/// - `missed`  — its scheduled time has passed with no taken/skip (denominator only), or
/// - upcoming  — its time hasn't arrived yet and there's no log (excluded entirely; not stored).
struct DayAdherence: Identifiable, Sendable, Hashable {
    let date: Date
    let taken: Int
    let skipped: Int
    let missed: Int

    var id: Date { date }
    /// Doses that count toward adherence on this day = taken + missed. Skipped doses and
    /// still-upcoming doses are excluded, so a Skip neither helps nor hurts the percentage.
    var counted: Int { taken + missed }
}

/// Pure adherence math over the same value snapshots the engine uses.
///
/// Definition (locked by tests): **adherence = taken ÷ (doses whose scheduled time has passed,
/// excluding explicit skips)**. A past-due untaken dose counts as missed the moment its time passes
/// — there is deliberately **no** grace window here (grace is a Today-screen "due vs missed"
/// colour concept, not an adherence concept). Upcoming doses are excluded; explicit Skips are
/// neutral. The chart, the header percentages, and "missed this week" all read this one series.
///
/// NOTE (flagged): expectations are reconstructed from the medicines' *current* `DoseTime` rules, so
/// editing a schedule will misattribute past days. Acceptable for this pass; a later analytics pass
/// should derive past expectations from `DoseLog` history.
enum AdherenceCalculator {
    /// The last `days` calendar days ending at `now` (oldest → newest).
    static func days(
        medicines: [MedicineSnapshot],
        logs: [DoseLogSnapshot],
        now: Date,
        days: Int,
        calendar: Calendar = .current
    ) -> [DayAdherence] {
        var result: [DayAdherence] = []
        var day = calendar.startOfDay(for: now)
        for _ in 0..<days {
            result.append(dayAdherence(on: day, medicines: medicines, logs: logs, now: now, calendar: calendar))
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day.addingTimeInterval(-86_400)
        }
        return result.reversed()   // oldest → newest
    }

    /// Every calendar day in `[from, to]` (inclusive, oldest → newest) for a report over an explicit
    /// range. `now` is the real current time, used only for the missed/upcoming cutoff, so a range
    /// ending today doesn't count today's not-yet-due doses as missed.
    static func days(
        medicines: [MedicineSnapshot],
        logs: [DoseLogSnapshot],
        from: Date,
        to: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> [DayAdherence] {
        var result: [DayAdherence] = []
        var day = calendar.startOfDay(for: from)
        let last = calendar.startOfDay(for: to)
        while day <= last {
            result.append(dayAdherence(on: day, medicines: medicines, logs: logs, now: now, calendar: calendar))
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        }
        return result
    }

    /// Shared per-day resolution used by both window queries above — the single place the adherence
    /// rules live. Resolved actions are LOG-DRIVEN — a `.taken`/`.skipped` log always counts, even if
    /// its slot precedes `createdAt` or no current rule reconstructs it (a real action is never
    /// invisible). Only the *missed* branch is schedule-reconstructed and floored to `[createdAt,
    /// endDate]` (so there are no phantom misses before a med existed or after a course ended).
    private static func dayAdherence(
        on day: Date, medicines: [MedicineSnapshot], logs: [DoseLogSnapshot], now: Date, calendar: Calendar
    ) -> DayAdherence {
        var taken = 0, skipped = 0, missed = 0
        for medicine in medicines {
            var accountedSlots: [Date] = []   // slots resolved by a log this day (avoid double-counting)
            var seenSlots = Set<Date>()        // de-dup rules resolving to the same slot → one dose, not two

            for rule in medicine.rules {
                guard let slot = rule.scheduledDate(on: day, calendar: calendar) else { continue }
                guard seenSlots.insert(slot).inserted else { continue }   // a duplicate rule counts once
                // The slot's LATEST log is its resolution — the same rule Today's `status()` uses, so
                // a take-then-skip (user corrected themselves) reads Skipped on BOTH screens instead
                // of Skipped on Today but taken in History. Resolved actions stay log-driven (no
                // lifetime floor); a lone snooze resolves nothing.
                switch ExecutionEngine.latestLog(medicineID: medicine.id, scheduledFor: slot, in: logs)?.action {
                case .taken:
                    taken += 1; accountedSlots.append(slot)        // resolved → always counts (no floor)
                case .skipped:
                    skipped += 1; accountedSlots.append(slot)      // neutral, but still displayed
                case .snoozed, nil:
                    if now > slot && ExecutionEngine.isWithinLifetime(
                        scheduledFor: slot, createdAt: medicine.createdAt,
                        endDate: medicine.endDate, calendar: calendar) {
                        missed += 1                                // unfulfilled in-lifetime slot
                    }
                    // else: upcoming, or a no-log slot outside the med's lifetime → not counted
                }
            }

            // Orphan logs: real takes/skips on this day whose slot no current rule reconstructs
            // (e.g. the schedule was edited after the dose). They must still count — resolved by the
            // SAME latest-log rule (pre-fix this counted whichever entry came first in the array).
            var orphanSlots: [Date] = []
            for entry in logs where entry.medicineID == medicine.id
                && calendar.isDate(entry.scheduledFor, inSameDayAs: day)
                && !accountedSlots.contains(where: { ExecutionEngine.sameSlot($0, entry.scheduledFor) })
                && !orphanSlots.contains(where: { ExecutionEngine.sameSlot($0, entry.scheduledFor) }) {
                orphanSlots.append(entry.scheduledFor)
            }
            for slot in orphanSlots {
                switch ExecutionEngine.latestLog(medicineID: medicine.id, scheduledFor: slot, in: logs)?.action {
                case .taken: taken += 1
                case .skipped: skipped += 1
                case .snoozed, nil: break   // a lone snooze never resolves a slot
                }
            }
        }
        return DayAdherence(date: day, taken: taken, skipped: skipped, missed: missed)
    }

    /// Taken ÷ (taken + missed) across the window, or `nil` when nothing counts in it.
    ///
    /// `nil` means "no data" — the UI must render it as neutral (a dash), never as 0% or 100%.
    /// This is the single adherence source the History header AND the chart read from, so they can
    /// never disagree. Pre-`createdAt` days, no-dose days, skips, and upcoming doses all contribute
    /// 0 to `counted`, so they drop out of both numerator and denominator automatically.
    static func rate(_ days: [DayAdherence]) -> Double? {
        let counted = days.reduce(0) { $0 + $1.counted }
        guard counted > 0 else { return nil }
        return Double(days.reduce(0) { $0 + $1.taken }) / Double(counted)
    }

    /// Total past-due-untaken doses across the window (the same `missed` the chart shows).
    static func missedCount(_ days: [DayAdherence]) -> Int {
        days.reduce(0) { $0 + $1.missed }
    }

    /// Taken ÷ counted across the window (1.0 when nothing counts). Retained for callers that want a
    /// non-optional value; prefer `rate(_:)` where "no data" must read as neutral.
    static func adherence(_ days: [DayAdherence]) -> Double {
        rate(days) ?? 1
    }

}
