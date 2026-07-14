import Foundation
import SwiftData

/// Pure refill / run-out projection. Stock is **derived** (never a mutated counter), matching how
/// adherence and streaks derive from `DoseLog`: remaining = units captured at the last refill minus the
/// units consumed by taken doses since. That keeps refill state automatically consistent with Undo and
/// with any log edit — there is nothing to increment/decrement per take.
enum RefillCalculator {
    /// Units left = `unitsAtRefill` − `unitsPerDose` × (taken doses on/after `refillDate`). `nil` when the
    /// medicine isn't tracking refills (no captured stock). Clamped at 0 (never negative).
    static func unitsRemaining(unitsAtRefill: Int?, refillDate: Date?, unitsPerDose: Int,
                               logs: [DoseLogSnapshot]) -> Int? {
        guard let unitsAtRefill, let refillDate else { return nil }
        let consumedDoses = logs.filter { $0.action == .taken && $0.actionedAt >= refillDate }.count
        return max(0, unitsAtRefill - max(0, unitsPerDose) * consumedDoses)
    }

    /// Average doses per day implied by the schedule, measured over `window` days forward from `now`, so a
    /// weekly / every-N-days pattern yields a fractional rate (e.g. every-3-days ≈ 0.33/day). 0 when nothing
    /// is scheduled. Uses the SAME `ExecutionEngine.scheduledSlots` projection Today/Week read.
    static func averageDosesPerDay(rules: [DoseSlotRule], from now: Date, window: Int = 28,
                                   calendar: Calendar = .current) -> Double {
        guard window > 0, !rules.isEmpty else { return 0 }
        let med = MedicineSnapshot(id: UUID(), name: "", dosage: nil, rules: rules)
        let start = calendar.startOfDay(for: now)
        var slots = 0
        for offset in 0..<window {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            slots += ExecutionEngine.scheduledSlots(medicines: [med], on: day, calendar: calendar).count
        }
        return Double(slots) / Double(window)
    }

    /// Projected whole days of supply = remaining ÷ (unitsPerDose × dosesPerDay), rounded down. `nil` when
    /// not tracking, or when there's no scheduled usage (a run-out can't be projected from zero consumption).
    static func daysOfSupply(remaining: Int?, unitsPerDose: Int, dosesPerDay: Double) -> Int? {
        guard let remaining, unitsPerDose > 0, dosesPerDay > 0 else { return nil }
        return Int((Double(remaining) / (Double(unitsPerDose) * dosesPerDay)).rounded(.down))
    }

    /// A refill reminder is due iff the medicine tracks a threshold and the projected supply is at/below it.
    static func needsRefillSoon(daysOfSupply: Int?, thresholdDays: Int?) -> Bool {
        guard let daysOfSupply, let thresholdDays else { return false }
        return daysOfSupply <= thresholdDays
    }
}

// MARK: - View-layer bridge (main actor): compute the display state from a live @Model + its logs.

@MainActor
extension Medicine {
    /// Whether this medicine is tracking stock for refill reminders (has both captured stock + a threshold).
    var isTrackingRefills: Bool { unitsAtRefill != nil && refillThresholdDays != nil }

    /// Projected whole days of supply remaining, or nil when not tracking / no scheduled usage. `logs` may
    /// be all `DoseLog`s — filtered to this medicine here.
    func daysOfSupply(logs: [DoseLog], now: Date = .now, calendar: Calendar = .current) -> Int? {
        let snaps = logs.filter { $0.medicineID == id }.map { $0.snapshot() }
        let remaining = RefillCalculator.unitsRemaining(unitsAtRefill: unitsAtRefill, refillDate: refillDate,
                                                        unitsPerDose: unitsPerDose, logs: snaps)
        let perDay = RefillCalculator.averageDosesPerDay(rules: doseTimes.map { $0.rule }, from: now, calendar: calendar)
        return RefillCalculator.daysOfSupply(remaining: remaining, unitsPerDose: unitsPerDose, dosesPerDay: perDay)
    }

    /// Units left right now (derived), or nil when not tracking.
    func unitsRemaining(logs: [DoseLog]) -> Int? {
        let snaps = logs.filter { $0.medicineID == id }.map { $0.snapshot() }
        return RefillCalculator.unitsRemaining(unitsAtRefill: unitsAtRefill, refillDate: refillDate,
                                               unitsPerDose: unitsPerDose, logs: snaps)
    }

    /// True when the projected supply is at/below the medicine's refill threshold.
    func needsRefillSoon(logs: [DoseLog], now: Date = .now, calendar: Calendar = .current) -> Bool {
        RefillCalculator.needsRefillSoon(daysOfSupply: daysOfSupply(logs: logs, now: now, calendar: calendar),
                                         thresholdDays: refillThresholdDays)
    }
}
