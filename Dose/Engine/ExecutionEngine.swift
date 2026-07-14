import Foundation

// MARK: - Value snapshots (Sendable; the engine never touches SwiftData)

/// A recurring dose rule as a value type. Mirrors `DoseTime` but carries no identity or status,
/// so the engine stays pure and `Sendable`. Repeat precedence: days-of-month → every-N-days →
/// specific weekdays → every day. This is the single source of truth for "does a dose fall on day X",
/// used by Today, streak, adherence, and the notification planner.
struct DoseSlotRule: Sendable, Hashable {
    let hour: Int
    let minute: Int
    let weekdays: [Int]      // non-empty = specific weekdays (Calendar weekday, 1 = Sunday)
    let intervalDays: Int    // >= 2 = every N days (requires anchorDate)
    let anchorDate: Date?    // first day of an interval pattern
    let daysOfMonth: [Int]   // non-empty = specific days of month (1...31)

    init(hour: Int, minute: Int, weekdays: [Int] = [], intervalDays: Int = 0,
         anchorDate: Date? = nil, daysOfMonth: [Int] = []) {
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.intervalDays = intervalDays
        self.anchorDate = anchorDate
        self.daysOfMonth = daysOfMonth
    }

    func applies(on day: Date, calendar: Calendar) -> Bool {
        let d = calendar.startOfDay(for: day)
        if !daysOfMonth.isEmpty {
            let dayOfMonth = calendar.component(.day, from: d)
            if daysOfMonth.contains(dayOfMonth) { return true }
            // Clamp: a requested day beyond THIS month's length fires on the month's last day, so a
            // "31st" (or "30th"/"29th") monthly dose is never silently skipped in Feb/Apr/Jun/Sep/Nov.
            // Only the true last day clamps, and only for requested days that don't exist this month —
            // so a real day (e.g. the 30th of a 31-day month) never spuriously also fires on the 31st.
            let lastDay = calendar.range(of: .day, in: .month, for: d)?.count ?? dayOfMonth
            return dayOfMonth == lastDay && daysOfMonth.contains { $0 > lastDay }
        }
        if intervalDays >= 2, let anchor = anchorDate {
            let a = calendar.startOfDay(for: anchor)
            guard d >= a else { return false }
            let elapsed = calendar.dateComponents([.day], from: a, to: d).day ?? 0
            return elapsed % intervalDays == 0
        }
        if !weekdays.isEmpty {
            return weekdays.contains(calendar.component(.weekday, from: d))
        }
        return true
    }

    func scheduledDate(on day: Date, calendar: Calendar) -> Date? {
        guard applies(on: day, calendar: calendar) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}

struct MedicineSnapshot: Sendable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let dosage: String?
    let rules: [DoseSlotRule]
    /// A dose can only be expected/missed on or after the start of this day. Defaults to
    /// `.distantPast` so callers/tests that don't care about the floor behave as "always existed".
    let createdAt: Date
    /// Last day of treatment, inclusive. `nil` = ongoing. After this day no doses are expected,
    /// scheduled, or counted — post-end days are neutral, exactly like pre-`createdAt` days.
    let endDate: Date?
    /// Optional "remind me N minutes before" heads-up (nil/0 = none). Used by the notification
    /// planner only; the adherence/Today engines ignore it.
    let leadTimeMinutes: Int?

    init(id: UUID, name: String, dosage: String?, rules: [DoseSlotRule],
         createdAt: Date = .distantPast, endDate: Date? = nil, leadTimeMinutes: Int? = nil) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.rules = rules
        self.createdAt = createdAt
        self.endDate = endDate
        self.leadTimeMinutes = leadTimeMinutes
    }
}

struct DoseLogSnapshot: Sendable, Hashable {
    let medicineID: UUID
    let scheduledFor: Date
    let action: DoseAction
    let actionedAt: Date
    /// For a `.snoozed` log, the chosen snooze length in minutes (nil = the default 10-min snooze).
    /// Drives BOTH the in-app snoozed-until (`status`) and the re-armed notification (the planner).
    let snoozeMinutes: Int?

    init(medicineID: UUID, scheduledFor: Date, action: DoseAction, actionedAt: Date, snoozeMinutes: Int? = nil) {
        self.medicineID = medicineID
        self.scheduledFor = scheduledFor
        self.action = action
        self.actionedAt = actionedAt
        self.snoozeMinutes = snoozeMinutes
    }
}

// MARK: - Derived UI status

/// Derived, read-time status for a dose slot. `.skipped` is a settled, neutral state produced when
/// the user explicitly skipped (e.g. from a notification); it is distinct from `.missed`, which is
/// a *computed* forgotten dose with no action at all.
enum DoseStatus: String, Sendable {
    case upcoming   // neutral — before due
    case due        // amber — due now, within grace
    case missed     // red — past grace with no action
    case taken      // green — settled
    case skipped    // neutral — explicitly skipped, settled
    case snoozed    // shows the new time

    /// The user already resolved this slot — further Take/Skip actions would stack contradictory
    /// logs (take-then-skip reads differently per surface); Undo is the correction path.
    var isSettled: Bool { self == .taken || self == .skipped }
}

struct TodayDose: Identifiable, Sendable, Hashable {
    let id: String
    let medicineID: UUID
    let medicineName: String
    let dosage: String?
    let scheduledFor: Date
    let status: DoseStatus
    let snoozedUntil: Date?
}

/// A scheduled dose occurrence WITHOUT any taken/skipped status — a pure projection of the rules on a
/// given day. The read-only "This week" view reads these; Today derives its `TodayDose` status on top
/// of the same slots, so the two can never disagree about what's scheduled when.
struct ScheduledSlot: Identifiable, Sendable, Hashable {
    let medicineID: UUID
    let medicineName: String
    let dosage: String?
    let scheduledFor: Date
    var id: String { "\(medicineID.uuidString)@\(Int(scheduledFor.timeIntervalSince1970))" }
}

// MARK: - The engine (pure)

enum ExecutionEngine {
    /// How long after the scheduled time a dose stays `.due` before it becomes `.missed`.
    ///
    /// GRACE IS A TODAY-ONLY, STILL-TAKEABLE AFFORDANCE — not a claim that the dose isn't missed. A dose
    /// within grace renders on Today with ALERT styling (red time / "Overdue"), never as neutral/upcoming.
    /// The adherence engine (`AdherenceCalculator.dayAdherence`/`missedEvents`) and the PDF deliberately
    /// apply NO grace — a past-due dose trends missed the moment its time passes — so analytics stay
    /// clinically honest and historical/PDF numbers are correct (product decision "Option 2", 2026-07-09).
    /// Today and analytics are therefore consistent in MEANING ("overdue, take now" vs "trending missed"),
    /// not identical in wording; that difference is intentional. Do not add grace to the adherence path.
    static let defaultGrace: TimeInterval = 60 * 60      // 60 minutes
    /// How long a snooze pushes the effective due time.
    static let snoozeInterval: TimeInterval = 10 * 60    // 10 minutes

    /// Pure: every scheduled dose occurrence on `day`, status-free, sorted by time. The single source
    /// of "what's scheduled when" — used directly by the week view and indirectly by `todaysDoses`, so
    /// the two never diverge. Respects the same bounds Today uses: nothing after the inclusive `endDate`
    /// and nothing before the medicine's `createdAt` day (a no-op for today/forward days).
    static func scheduledSlots(
        medicines: [MedicineSnapshot],
        on day: Date,
        calendar: Calendar = .current
    ) -> [ScheduledSlot] {
        let dayStart = calendar.startOfDay(for: day)
        var result: [ScheduledSlot] = []
        for medicine in medicines {
            // PRESENCE is day-level: a medicine shows on its creation day (and through its inclusive end
            // day) so a freshly-added med appears on Today. Whether a given slot can be *missed* is a
            // separate, instant-level question handled in `todaysDoses` via `isWithinLifetime`.
            if let endDate = medicine.endDate, dayStart > calendar.startOfDay(for: endDate) { continue }
            if dayStart < calendar.startOfDay(for: medicine.createdAt) { continue }
            // De-dup rules that resolve to the same minute (e.g. two identical dose times) so one dose
            // never becomes two slots with a colliding `id` — which would garble the Today/Week ForEach
            // and double-count adherence. (NotificationPlanner already de-dups; match it here.)
            var seenTimes = Set<Date>()
            for rule in medicine.rules {
                guard let scheduledFor = rule.scheduledDate(on: day, calendar: calendar) else { continue }
                guard seenTimes.insert(scheduledFor).inserted else { continue }
                result.append(ScheduledSlot(medicineID: medicine.id, medicineName: medicine.name,
                                            dosage: medicine.dosage, scheduledFor: scheduledFor))
            }
        }
        return result.sorted { $0.scheduledFor < $1.scheduledFor }
    }

    /// Pure function: today's doses with a derived status, built on `scheduledSlots(on: now)` so the
    /// "what's scheduled" computation is shared with the week view. "Missed" is computed here from the
    /// grace window — there is no midnight reset job anywhere.
    static func todaysDoses(
        medicines: [MedicineSnapshot],
        logs: [DoseLogSnapshot],
        now: Date,
        grace: TimeInterval = defaultGrace,
        calendar: Calendar = .current
    ) -> [TodayDose] {
        // A med shows on its creation DAY (day-level presence, via scheduledSlots) so a freshly-added
        // medicine appears on Today. But a slot earlier than the exact creation INSTANT was never
        // actionable, so it must never read as "missed" — it stays takeable (`.due`). This is the SAME
        // lifetime rule adherence & streak use for missability; presence and missability differ only on
        // the creation day, which is exactly where the Today↔History "missed" mismatch came from.
        let byID = Dictionary(medicines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return scheduledSlots(medicines: medicines, on: now, calendar: calendar).map { slot in
            let latest = latestLog(medicineID: slot.medicineID, scheduledFor: slot.scheduledFor, in: logs)
            let canBeMissed = byID[slot.medicineID].map {
                isWithinLifetime(scheduledFor: slot.scheduledFor, createdAt: $0.createdAt,
                                 endDate: $0.endDate, calendar: calendar)
            } ?? true
            let (status, snoozedUntil) = status(scheduledFor: slot.scheduledFor, latest: latest,
                                                now: now, grace: grace, canBeMissed: canBeMissed)
            return TodayDose(id: slot.id, medicineID: slot.medicineID, medicineName: slot.medicineName,
                             dosage: slot.dosage, scheduledFor: slot.scheduledFor,
                             status: status, snoozedUntil: snoozedUntil)
        }
    }

    // MARK: Internal helpers (shared with StreakCalculator)

    static func sameSlot(_ a: Date, _ b: Date) -> Bool { abs(a.timeIntervalSince(b)) < 1 }

    static func latestLog(medicineID: UUID, scheduledFor: Date, in logs: [DoseLogSnapshot]) -> DoseLogSnapshot? {
        let slotLogs = logs.filter { $0.medicineID == medicineID && sameSlot($0.scheduledFor, scheduledFor) }
        // A terminal action (taken/skipped) SETTLES the slot: once one exists, a later `.snoozed` can't
        // reopen it and erase the take (S4). Among same-precedence logs the latest wins; an exact
        // `actionedAt` tie breaks deterministically by action rank (S3) so Today, History, and adherence
        // — which receive logs in different orderings — always resolve a slot identically.
        let terminal = slotLogs.filter { $0.action == .taken || $0.action == .skipped }
        let pool = terminal.isEmpty ? slotLogs : terminal
        return pool.max {
            $0.actionedAt != $1.actionedAt ? $0.actionedAt < $1.actionedAt : actionRank($0.action) < actionRank($1.action)
        }
    }

    /// Deterministic tie-break for logs with an identical `actionedAt` (higher wins): taken > skipped > snoozed.
    private static func actionRank(_ action: DoseAction) -> Int {
        switch action {
        case .taken: return 2
        case .skipped: return 1
        case .snoozed: return 0
        }
    }

    static func status(
        scheduledFor: Date,
        latest: DoseLogSnapshot?,
        now: Date,
        grace: TimeInterval,
        canBeMissed: Bool = true
    ) -> (DoseStatus, Date?) {
        guard let latest else {
            return (unactioned(due: scheduledFor, now: now, grace: grace, canBeMissed: canBeMissed), nil)
        }
        switch latest.action {
        case .taken:
            return (.taken, nil)
        case .skipped:
            return (.skipped, nil)
        case .snoozed:
            // Honor a variable snooze length (from the in-app action sheet); default 10 min.
            let interval = latest.snoozeMinutes.map { TimeInterval($0 * 60) } ?? snoozeInterval
            let until = latest.actionedAt.addingTimeInterval(interval)
            if now < until { return (.snoozed, until) }
            // Snooze elapsed with no further action → re-evaluate against the snoozed time.
            return (unactioned(due: until, now: now, grace: grace, canBeMissed: canBeMissed), nil)
        }
    }

    /// `canBeMissed == false` for a slot before the medicine's creation instant: it was never actionable,
    /// so past its grace it stays takeable (`.due`) instead of a phantom `.missed` that History (which
    /// floors missed at the same instant) would never count — the two screens then agree.
    private static func unactioned(due: Date, now: Date, grace: TimeInterval, canBeMissed: Bool = true) -> DoseStatus {
        if now < due { return .upcoming }
        if now <= due.addingTimeInterval(grace) { return .due }
        return canBeMissed ? .missed : .due
    }

    /// The ONE medicine-lifetime rule, shared by Today's slot projection (`scheduledSlots`), adherence's
    /// missed reconstruction, and the streak — so a dose from before the med existed (or after its course
    /// ended) is treated identically everywhere and can't be a phantom "missed" on one screen while
    /// another ignores it. `createdAt` is floored at the exact instant (a dose scheduled earlier on the
    /// creation day was never actionable); `endDate` is an inclusive, day-level ceiling.
    static func isWithinLifetime(scheduledFor: Date, createdAt: Date, endDate: Date?,
                                 calendar: Calendar = .current) -> Bool {
        guard scheduledFor >= createdAt else { return false }
        if let endDate, calendar.startOfDay(for: scheduledFor) > calendar.startOfDay(for: endDate) {
            return false
        }
        return true
    }
}

// MARK: - @Model → snapshot mapping (called on the main actor by the view layer)

extension Medicine {
    func snapshot() -> MedicineSnapshot {
        MedicineSnapshot(
            id: id,
            name: name,
            dosage: dosage,
            rules: doseTimes.map {
                DoseSlotRule(hour: $0.hour, minute: $0.minute, weekdays: $0.weekdays,
                             intervalDays: $0.intervalDays, anchorDate: $0.anchorDate, daysOfMonth: $0.daysOfMonth)
            },
            createdAt: createdAt,
            endDate: endDate,
            leadTimeMinutes: leadTimeMinutes
        )
    }
}

extension DoseLog {
    func snapshot() -> DoseLogSnapshot {
        DoseLogSnapshot(medicineID: medicineID, scheduledFor: scheduledFor, action: action,
                        actionedAt: actionedAt, snoozeMinutes: snoozeMinutes)
    }
}

extension ExecutionEngine {
    /// Convenience for the view layer: filters to confirmed + active medicines and maps `@Model`
    /// objects to snapshots before running the pure core.
    @MainActor
    static func todaysDoses(confirmedMedicines: [Medicine], logs: [DoseLog], now: Date = .now) -> [TodayDose] {
        let meds = Medicine.activeConfirmed(confirmedMedicines).map { $0.snapshot() }
        return todaysDoses(medicines: meds, logs: logs.map { $0.snapshot() }, now: now)
    }

    /// Convenience for the week view: the SAME confirmed+active filtering as `todaysDoses`, projected to
    /// status-free scheduled slots for an arbitrary `day`.
    @MainActor
    static func scheduledSlots(confirmedMedicines: [Medicine], on day: Date, calendar: Calendar = .current) -> [ScheduledSlot] {
        let meds = Medicine.activeConfirmed(confirmedMedicines).map { $0.snapshot() }
        return scheduledSlots(medicines: meds, on: day, calendar: calendar)
    }
}
