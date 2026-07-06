import Foundation

/// A scheduled local reminder → a one-shot trigger, identified PER OCCURRENCE so a single slot can be
/// cancelled when its dose is taken/skipped (a repeating trigger can't cancel one occurrence — the
/// double-dose bug). Three kinds, distinguished by the flags:
/// - **on-time** (`!isEscalation && leadMinutes == nil`): fires AT the dose time. First budget claim.
/// - **escalation** (`isEscalation`): fires ~10 min after, if still unactioned.
/// - **lead-time** (`leadMinutes != nil`): optional heads-up before the dose. Lowest budget priority.
/// All are windowed within `defaultWindow` and refilled by `BackgroundRefresh` (and every foreground
/// reschedule) — the deliberate trade for making a single occurrence cancellable.
struct WindowedReminder: Sendable, Hashable {
    let id: String
    let medicineID: UUID
    let medicineName: String
    let dosage: String?
    let fireDate: Date       // when this notification fires
    let scheduledFor: Date   // the dose occurrence it belongs to
    let isEscalation: Bool
    /// Non-nil when this is an optional "heads-up" reminder N minutes BEFORE the dose. Defaulted so
    /// on-time / escalation construction is unchanged.
    var leadMinutes: Int? = nil
}

struct NotificationPlan: Sendable {
    /// On-time dose reminders (every scheduled occurrence in the horizon). First claim on the budget.
    let onTime: [WindowedReminder]
    let escalations: [WindowedReminder]
    let leadTime: [WindowedReminder]
    /// Pending "Remind in 10 min" one-shots rebuilt from the log. A snooze exists ONLY in the
    /// notification center, and `reschedule` wipes every pending request — so unless the plan re-arms
    /// it, any reschedule (app foreground, background refresh, editing any medicine) silently destroys
    /// the promised reminder while Today keeps showing "snoozed until…". Imminent by construction
    /// (≤ 10 min out), so they claim budget ahead of on-time.
    let snoozes: [WindowedReminder]
    /// True only when ON-TIME reminders alone exceed the budget and had to be trimmed (the soonest
    /// survive; farther occurrences are picked up by the next refill). On-time is NEVER dropped in
    /// favour of escalations or lead-time.
    let baseTruncated: Bool

    /// Every reminder, in priority order — what the scheduler submits.
    var windowed: [WindowedReminder] { snoozes + onTime + escalations + leadTime }
    var total: Int { snoozes.count + onTime.count + escalations.count + leadTime.count }
}

/// Pure planner for the local-notification schedule. Every dose occurrence in the horizon becomes a
/// per-occurrence one-shot so it's individually cancellable. Honors the 64-slot iOS cap in priority
/// order: **on-time first** (soonest-first when trimming), then escalations, then lead-time. A dose
/// already taken/skipped is never (re)scheduled — that's what stops the on-time reminder from firing
/// for an already-recorded dose, and stops a refill from resurrecting it.
enum NotificationPlanner {
    static let maxPending = 64
    static let escalationDelay: TimeInterval = 10 * 60          // ~10 min after the original
    /// How far ahead one-shots are scheduled. A week of runway so background refresh (BGAppRefreshTask,
    /// discretionary) has slack to top it up before it drains; budget trimming below bounds slot cost.
    static let defaultWindow: TimeInterval = 7 * 24 * 3600

    static func plan(
        medicines: [MedicineSnapshot],
        logs: [DoseLogSnapshot] = [],
        now: Date,
        escalationEnabled: Bool,
        budget: Int = maxPending,
        window: TimeInterval = defaultWindow,
        calendar: Calendar = .current
    ) -> NotificationPlan {
        let end = now.addingTimeInterval(window)

        var onTimeSeen = Set<String>(); var onTime: [WindowedReminder] = []
        var escSeen = Set<String>();    var escalations: [WindowedReminder] = []
        var leadSeen = Set<String>();   var leadtime: [WindowedReminder] = []

        for medicine in medicines {
            // A finite course caps its window at the inclusive end day; an ongoing med uses the full
            // horizon. Once `now` is past the end day there are zero occurrences.
            let medEnd: Date = {
                guard let endDate = medicine.endDate else { return end }
                let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
                return min(end, endOfDay)
            }()

            for rule in medicine.rules {
                for occ in occurrences(of: rule, from: now, to: medEnd, calendar: calendar) {
                    // Never (re)schedule a reminder for a dose already taken/skipped — this is what
                    // prevents the on-time "Time for X" from firing for an already-recorded dose, and a
                    // foreground/background refill from resurrecting it. (The take itself also cancels
                    // the pending one-shot immediately; this stops it ever coming back.)
                    guard !isResolved(medicine.id, occ, logs) else { continue }

                    let onID = onTimeID(medicine.id, occ)
                    if onTimeSeen.insert(onID).inserted {
                        onTime.append(WindowedReminder(
                            id: onID, medicineID: medicine.id, medicineName: medicine.name, dosage: medicine.dosage,
                            fireDate: occ, scheduledFor: occ, isEscalation: false))
                    }

                    if escalationEnabled {
                        let fire = occ.addingTimeInterval(escalationDelay)
                        if fire > now {
                            let id = escID(medicine.id, occ)
                            if escSeen.insert(id).inserted {
                                escalations.append(WindowedReminder(
                                    id: id, medicineID: medicine.id, medicineName: medicine.name, dosage: medicine.dosage,
                                    fireDate: fire, scheduledFor: occ, isEscalation: true))
                            }
                        }
                    }

                    // Optional lead-time heads-up at (occ - leadMinutes). `scheduledFor = occ` so a Take
                    // from the heads-up records the right dose (and cancels the rest of the slot).
                    if let lead = medicine.leadTimeMinutes, lead > 0 {
                        let fire = occ.addingTimeInterval(TimeInterval(-lead * 60))
                        if fire > now {
                            let id = leadID(medicine.id, occ)
                            if leadSeen.insert(id).inserted {
                                leadtime.append(WindowedReminder(
                                    id: id, medicineID: medicine.id, medicineName: medicine.name, dosage: medicine.dosage,
                                    fireDate: fire, scheduledFor: occ, isEscalation: false, leadMinutes: lead))
                            }
                        }
                    }
                }
            }
        }

        // Re-arm pending snoozes from the log. The slot's LATEST log decides (the same rule as
        // `ExecutionEngine.status`), so what re-arms here is exactly what the UI shows as snoozed;
        // a later take/skip makes the latest log non-snoozed and nothing re-arms. Meds not in the
        // plan input (archived/deleted) correctly lose their snoozes with the wipe.
        var snoozes: [WindowedReminder] = []
        var snoozeSeen = Set<String>()
        let medByID = Dictionary(medicines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for entry in logs where entry.action == .snoozed {
            let id = snoozeID(entry.medicineID, entry.scheduledFor)
            guard !snoozeSeen.contains(id), let med = medByID[entry.medicineID] else { continue }
            guard let latest = ExecutionEngine.latestLog(medicineID: entry.medicineID,
                                                         scheduledFor: entry.scheduledFor, in: logs),
                  latest.action == .snoozed else { continue }
            let fire = latest.actionedAt.addingTimeInterval(escalationDelay)
            guard fire > now else { continue }   // the snooze window already elapsed — nothing to re-arm
            snoozeSeen.insert(id)
            snoozes.append(WindowedReminder(id: id, medicineID: med.id, medicineName: med.name,
                                            dosage: med.dosage, fireDate: fire,
                                            scheduledFor: entry.scheduledFor, isEscalation: false))
        }
        snoozes = Array(snoozes.sorted { $0.fireDate < $1.fireDate }.prefix(budget))

        // Budget — priority order preserved. Snoozes (imminent, few) claim first, then on-time trims
        // soonest-first, so the nearest doses are always covered and on-time is never sacrificed for
        // escalation/lead-time.
        var baseTruncated = false
        onTime.sort { $0.fireDate < $1.fireDate }
        let onTimeBudget = max(0, budget - snoozes.count)
        if onTime.count > onTimeBudget {
            onTime = Array(onTime.prefix(onTimeBudget))
            baseTruncated = true
        }
        var remaining = max(0, onTimeBudget - onTime.count)

        // Escalations next, soonest-first (gets nothing when on-time filled the budget → remaining 0).
        let chosenEscalations = remaining > 0
            ? Array(escalations.sorted { $0.fireDate < $1.fireDate }.prefix(remaining))
            : []
        remaining = max(0, remaining - chosenEscalations.count)

        // Lead-time heads-ups are LOWEST priority — only whatever budget is still left.
        let chosenLeadtime = remaining > 0
            ? Array(leadtime.sorted { $0.fireDate < $1.fireDate }.prefix(remaining))
            : []

        return NotificationPlan(onTime: onTime, escalations: chosenEscalations,
                                leadTime: chosenLeadtime, snoozes: snoozes, baseTruncated: baseTruncated)
    }

    // MARK: - Identifiers (deterministic per occurrence, so one slot can be removed without others)

    static func onTimeID(_ medicineID: UUID, _ scheduledFor: Date) -> String {
        "ontime.\(medicineID.uuidString).\(Int(scheduledFor.timeIntervalSince1970))"
    }

    static func escID(_ medicineID: UUID, _ scheduledFor: Date) -> String {
        "esc.\(medicineID.uuidString).\(Int(scheduledFor.timeIntervalSince1970))"
    }

    static func leadID(_ medicineID: UUID, _ scheduledFor: Date) -> String {
        "lead.\(medicineID.uuidString).\(Int(scheduledFor.timeIntervalSince1970))"
    }

    /// A snooze ("remind me in 10 min") is tied to the SAME occurrence it postpones, with a deterministic
    /// id so it's cancellable by `cancelSlot` like the others (was a random uuid → uncancellable, which
    /// let a snooze fire for an already-taken dose).
    static func snoozeID(_ medicineID: UUID, _ scheduledFor: Date) -> String {
        "snooze.\(medicineID.uuidString).\(Int(scheduledFor.timeIntervalSince1970))"
    }

    /// Every reminder id for one dose occurrence — removed together when the dose is taken/skipped so
    /// NO further prompt (on-time, escalation, lead-time, OR a pending snooze) fires for that slot.
    static func slotIDs(_ medicineID: UUID, _ scheduledFor: Date) -> [String] {
        [onTimeID(medicineID, scheduledFor), escID(medicineID, scheduledFor),
         leadID(medicineID, scheduledFor), snoozeID(medicineID, scheduledFor)]
    }

    // MARK: - Helpers

    /// True when this occurrence already has a `.taken`/`.skipped` log (so it must not be scheduled).
    private static func isResolved(_ medicineID: UUID, _ occ: Date, _ logs: [DoseLogSnapshot]) -> Bool {
        for entry in logs {
            guard entry.medicineID == medicineID else { continue }
            guard entry.action == .taken || entry.action == .skipped else { continue }
            if ExecutionEngine.sameSlot(entry.scheduledFor, occ) { return true }
        }
        return false
    }

    /// All concrete occurrences of a rule in (now, end] (inclusive of `end`), by day-walk. Handles every
    /// pattern (daily / specific-weekday / every-N-days / days-of-month) via `rule.scheduledDate`.
    private static func occurrences(of rule: DoseSlotRule, from now: Date, to end: Date, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: now)
        while day <= end {
            if let occ = rule.scheduledDate(on: day, calendar: calendar), occ >= now, occ <= end {
                result.append(occ)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}
