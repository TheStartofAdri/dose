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
    /// One "running low — refill soon" reminder per medicine that tracks stock and is projected to cross
    /// its refill threshold within the horizon. LOWEST priority — filled only from leftover budget so it
    /// never displaces a dose reminder — and not tied to any dose occurrence (wiped/rebuilt each reschedule).
    let refills: [WindowedReminder]
    /// When doses exist BEYOND this plan's coverage (past the horizon, or past the truncation point
    /// when the 64-cap trims), one "open Dose to refresh" sentinel fires at the moment coverage runs
    /// out. One-shots are refilled only by app-opens and discretionary background refresh — without
    /// this, a user who does neither gets total reminder silence with no signal (the in-app
    /// truncation banner is invisible to someone not opening the app). `nil` = everything the
    /// schedule will ever need is already covered (e.g. a course ending inside the window).
    let sentinelFireDate: Date?
    /// True only when ON-TIME reminders alone exceed the budget and had to be trimmed (the soonest
    /// survive; farther occurrences are picked up by the next refill). On-time is NEVER dropped in
    /// favour of escalations or lead-time.
    let baseTruncated: Bool

    /// Every reminder, in priority order — what the scheduler submits.
    var windowed: [WindowedReminder] { snoozes + onTime + escalations + leadTime + refills }
    var total: Int {
        snoozes.count + onTime.count + escalations.count + leadTime.count + refills.count
            + (sentinelFireDate == nil ? 0 : 1)
    }
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

        // Index logs by medicineID ONCE, so the per-occurrence resolution check + the per-medicine refill
        // filter scan only that medicine's logs instead of the whole table. Behavior-identical (both were
        // already filtering by medicineID); turns the hot O(occurrences × allLogs) into O(allLogs) index +
        // O(occurrences × logsForThatMed). `plan` runs on every foreground and every non-dose write.
        let logsByMed = Dictionary(grouping: logs, by: { $0.medicineID })

        var hasBeyondWindow = false
        for medicine in medicines {
            // A finite course caps its window at the inclusive end day; an ongoing med uses the full
            // horizon. Once `now` is past the end day there are zero occurrences.
            let scheduleEnd: Date? = medicine.endDate.map {
                calendar.date(bySettingHour: 23, minute: 59, second: 59, of: $0) ?? $0
            }
            let medEnd = scheduleEnd.map { min(end, $0) } ?? end
            // An ongoing med (or a course outlasting the horizon) has doses BEYOND what this plan
            // can cover — the sentinel below must warn when coverage runs out.
            if !medicine.rules.isEmpty, scheduleEnd.map({ $0 > end }) ?? true { hasBeyondWindow = true }

            for rule in medicine.rules {
                for occ in occurrences(of: rule, from: now, to: medEnd, calendar: calendar) {
                    // Never (re)schedule a reminder for a dose already taken/skipped — this is what
                    // prevents the on-time "Time for X" from firing for an already-recorded dose, and a
                    // foreground/background refill from resurrecting it. (The take itself also cancels
                    // the pending one-shot immediately; this stops it ever coming back.)
                    guard !isResolved(occ, in: logsByMed[medicine.id] ?? []) else { continue }

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
            // Honor a variable snooze length chosen in the in-app action sheet; default 10 min.
            let snoozeDelay = latest.snoozeMinutes.map { TimeInterval($0 * 60) } ?? escalationDelay
            let fire = latest.actionedAt.addingTimeInterval(snoozeDelay)
            guard fire > now else { continue }   // the snooze window already elapsed — nothing to re-arm
            snoozeSeen.insert(id)
            snoozes.append(WindowedReminder(id: id, medicineID: med.id, medicineName: med.name,
                                            dosage: med.dosage, fireDate: fire,
                                            scheduledFor: entry.scheduledFor, isEscalation: false))
        }
        // Budget — priority order preserved. Snoozes (imminent, few) claim first, then on-time trims
        // soonest-first, so the nearest doses are always covered and on-time is never sacrificed for
        // escalation/lead-time.
        var baseTruncated = false
        onTime.sort { $0.fireDate < $1.fireDate }
        // The refill sentinel needs a GUARANTEED slot whenever doses exist beyond this plan's coverage.
        // Reserve it BEFORE trimming EITHER snoozes or on-time (using the untrimmed demand), so even the
        // fully-loaded case — enough pending snoozes to fill the cap by themselves — can't push the total
        // past the 64 limit and make iOS silently drop a scheduled request (previously `snoozes.prefix(
        // budget)` ignored the sentinel → 65 pending). For normal loads (few snoozes) this is a no-op.
        let needsSentinel = hasBeyondWindow || (snoozes.count + onTime.count) > budget
        let effectiveBudget = max(0, budget - (needsSentinel ? 1 : 0))
        snoozes = Array(snoozes.sorted { $0.fireDate < $1.fireDate }.prefix(effectiveBudget))
        let onTimeBudget = max(0, effectiveBudget - snoozes.count)
        var sentinelFireDate: Date?
        if onTime.count > onTimeBudget {
            sentinelFireDate = onTime[onTimeBudget].fireDate   // when the first UNcovered dose is due
            onTime = Array(onTime.prefix(onTimeBudget))
            baseTruncated = true
        } else if needsSentinel {
            sentinelFireDate = end                             // coverage runs out at the horizon
        }
        var remaining = max(0, onTimeBudget - onTime.count)

        // Escalations next, soonest-first (gets nothing when on-time filled the budget → remaining 0).
        let chosenEscalations = remaining > 0
            ? Array(escalations.sorted { $0.fireDate < $1.fireDate }.prefix(remaining))
            : []
        remaining = max(0, remaining - chosenEscalations.count)

        // Lead-time heads-ups are next-lowest priority — only whatever budget is still left.
        let chosenLeadtime = remaining > 0
            ? Array(leadtime.sorted { $0.fireDate < $1.fireDate }.prefix(remaining))
            : []
        remaining = max(0, remaining - chosenLeadtime.count)

        // Refill "running low" reminders are the LOWEST priority — they must never displace a dose
        // reminder, so they take only leftover budget.
        let refills = refillReminders(medicines: medicines, logsByMed: logsByMed, now: now, window: window, calendar: calendar)
        let chosenRefills = remaining > 0
            ? Array(refills.sorted { $0.fireDate < $1.fireDate }.prefix(remaining))
            : []

        return NotificationPlan(onTime: onTime, escalations: chosenEscalations,
                                leadTime: chosenLeadtime, snoozes: snoozes, refills: chosenRefills,
                                sentinelFireDate: sentinelFireDate, baseTruncated: baseTruncated)
    }

    /// One "running low — refill soon" reminder per stock-tracking medicine whose projected run-out
    /// crosses its threshold within the horizon. Fires at 10:00 on the crossing day (or the next morning
    /// if that's already past), so it's stable across reschedules. Pure; uses `RefillCalculator`.
    private static func refillReminders(medicines: [MedicineSnapshot], logsByMed: [UUID: [DoseLogSnapshot]],
                                        now: Date, window: TimeInterval, calendar: Calendar) -> [WindowedReminder] {
        let windowDays = max(1, Int(window / 86_400))
        var out: [WindowedReminder] = []
        for medicine in medicines {
            guard let threshold = medicine.refillThresholdDays, medicine.unitsAtRefill != nil,
                  !medicine.rules.isEmpty else { continue }
            let medLogs = logsByMed[medicine.id] ?? []
            let remaining = RefillCalculator.unitsRemaining(unitsAtRefill: medicine.unitsAtRefill,
                                                            refillDate: medicine.refillDate,
                                                            unitsPerDose: medicine.unitsPerDose, logs: medLogs,
                                                            medicineID: medicine.id)
            let perDay = RefillCalculator.averageDosesPerDay(rules: medicine.rules, from: now, window: windowDays,
                                                             createdAt: medicine.createdAt, endDate: medicine.endDate,
                                                             calendar: calendar)
            guard let days = RefillCalculator.daysOfSupply(remaining: remaining,
                                                           unitsPerDose: medicine.unitsPerDose,
                                                           dosesPerDay: perDay) else { continue }
            let offsetDays = max(0, days - threshold)
            guard offsetDays <= windowDays else { continue }   // crossing too far out — a later refill picks it up
            let crossingDay = calendar.date(byAdding: .day, value: offsetDays, to: calendar.startOfDay(for: now)) ?? now
            var fire = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: crossingDay) ?? crossingDay
            if fire <= now {
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
                fire = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow) ?? now.addingTimeInterval(3600)
            }
            out.append(WindowedReminder(id: medRefillID(medicine.id), medicineID: medicine.id,
                                        medicineName: medicine.name, dosage: medicine.dosage,
                                        fireDate: fire, scheduledFor: fire, isEscalation: false))
        }
        return out
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

    /// The single coverage-end sentinel (`NotificationPlan.sentinelFireDate`) — one per plan, replaced
    /// wholesale by every reschedule, never matched by `slotIDs`/`cancelSlot`.
    static let refillSentinelID = "refill.sentinel"

    /// The one medication-refill ("running low") reminder per medicine — replaced wholesale by every
    /// reschedule, never tied to a dose occurrence (so not matched by `slotIDs`/`cancelSlot`).
    static func medRefillID(_ medicineID: UUID) -> String {
        "medrefill.\(medicineID.uuidString)"
    }

    /// Every reminder id for one dose occurrence — removed together when the dose is taken/skipped so
    /// NO further prompt (on-time, escalation, lead-time, OR a pending snooze) fires for that slot.
    static func slotIDs(_ medicineID: UUID, _ scheduledFor: Date) -> [String] {
        [onTimeID(medicineID, scheduledFor), escID(medicineID, scheduledFor),
         leadID(medicineID, scheduledFor), snoozeID(medicineID, scheduledFor)]
    }

    // MARK: - Helpers

    /// True when this occurrence already has a `.taken`/`.skipped` log (so it must not be scheduled).
    /// `medLogs` is the pre-indexed subset for one medicine (see `logsByMed` in `plan`).
    private static func isResolved(_ occ: Date, in medLogs: [DoseLogSnapshot]) -> Bool {
        for entry in medLogs {
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
