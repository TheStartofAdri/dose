import Foundation
import SwiftUI

/// One editable dose time carrying a STABLE identity. The schedule editor binds and deletes rows by
/// this `id`, not by array index — index identity plus index-subscript bindings crash with "Index
/// out of range" when a row is removed (the torn-down row re-reads its now-out-of-bounds binding).
struct TimedDose: Identifiable, Equatable {
    let id: UUID
    var time: Date
    init(id: UUID = UUID(), time: Date) { self.id = id; self.time = time }
}

/// Editable, reference-type state behind the review/confirm gate. Built from a `DraftMedication`
/// (AI/scan) or from scratch (manual), edited in the UI, then mapped to a confirmed `Medicine`.
@Observable
final class EditableDraft: Identifiable {
    enum Source { case manual, ai, scan }

    /// How often the dose repeats. Drives the "Repeat" UI and maps to `DoseTime` fields.
    enum RepeatMode: String, CaseIterable, Identifiable {
        case everyday, weekdays, everyNDays, daysOfMonth
        var id: String { rawValue }
        var label: String {
            switch self {
            case .everyday: "Every day"
            case .weekdays: "Specific weekdays"
            case .everyNDays: "Every N days"
            case .daysOfMonth: "Days of month"
            }
        }
    }

    /// How long the treatment lasts. Resolves to `Medicine.endDate` (nil = ongoing).
    enum DurationMode: String, CaseIterable, Identifiable {
        case ongoing, days, until
        var id: String { rawValue }
        var label: String {
            switch self {
            case .ongoing: "Ongoing"
            case .days: "For a number of days"
            case .until: "Until a date"
            }
        }
        /// Compact label for the segmented picker.
        var shortLabel: String {
            switch self {
            case .ongoing: "Ongoing"
            case .days: "Days"
            case .until: "Until"
            }
        }
    }

    let id = UUID()
    var name: String
    var dosage: String
    var form: String
    var quantity: String
    /// Dose times as identified rows (only hour/minute are meaningful). Stored with stable ids so the
    /// editor's ForEach/bindings survive deletion; `times` is the plain `[Date]` view every other
    /// consumer (mapping, tests) reads.
    var timedDoses: [TimedDose]
    var times: [Date] { timedDoses.map(\.time) }

    var repeatMode: RepeatMode
    var weekdays: Set<Int>       // Calendar weekday numbers (1 = Sunday) — repeatMode == .weekdays
    var intervalDays: Int        // repeatMode == .everyNDays (>= 2)
    /// The every-N-days cycle start carried over from the rule being edited. Nil for a new schedule
    /// (or a mode switch), which anchors at the creation day — but an EDIT must keep the original
    /// anchor, or saving an unrelated change (name, icon…) silently phase-shifts the dosing cycle.
    var anchorDate: Date?
    var daysOfMonth: Set<Int>    // 1...31 — repeatMode == .daysOfMonth

    // Extras (icon/colour, treatment duration, instructions) — edited in the post-save/extras editor.
    var iconName: String?
    var colorHex: String?
    var instructions: String
    var durationMode: DurationMode
    var durationDays: Int        // durationMode == .days (>= 1)
    var endDateChoice: Date      // durationMode == .until
    var leadTimeMinutes: Int?    // optional "remind me N min before" heads-up (nil = none)

    // Refill reminder config (v7). The stock BASELINE lives on the Medicine; this flow re-baselines it
    // only when `refillNewStock` is provided (blank = keep current, so an unrelated edit never resets
    // consumption). `existing*` carry the medicine's current baseline through an edit unchanged.
    var refillTrackingOn: Bool
    var refillThresholdDays: Int     // remind when projected days-of-supply ≤ this (when tracking)
    var unitsPerDose: Int            // units consumed per dose
    var refillNewStock: Int?         // nil = keep the baseline; a value = set/replace it (refillDate → now)
    let isEditingExisting: Bool      // true when editing a saved medicine (drives refill re-baseline UX)
    private let existingUnitsAtRefill: Int?
    private let existingRefillDate: Date?

    // Parser metadata — drives the review screen's confidence treatment.
    let source: Source
    let uncertainFields: Set<String>
    let scheduleInferred: Bool
    let confidence: Confidence

    /// Low-confidence fields the user must review before confirming. Cleared field-by-field as the
    /// user edits OR explicitly acknowledges ("Looks right").
    private(set) var mustEdit: Set<String>
    /// Fields the user explicitly acknowledged as correct without editing (shows a "Reviewed" mark).
    private(set) var acknowledged: Set<String> = []

    init(
        name: String = "",
        dosage: String = "",
        form: String = "",
        quantity: String = "",
        times: [Date],
        repeatMode: RepeatMode = .everyday,
        weekdays: Set<Int> = [],
        intervalDays: Int = 2,
        anchorDate: Date? = nil,
        daysOfMonth: Set<Int> = [],
        iconName: String? = nil,
        colorHex: String? = nil,
        instructions: String = "",
        durationMode: DurationMode = .ongoing,
        durationDays: Int = 7,
        endDateChoice: Date = .now,
        leadTimeMinutes: Int? = nil,
        refillTrackingOn: Bool = false,
        refillThresholdDays: Int = 7,
        unitsPerDose: Int = 1,
        refillNewStock: Int? = nil,
        isEditingExisting: Bool = false,
        existingUnitsAtRefill: Int? = nil,
        existingRefillDate: Date? = nil,
        source: Source = .manual,
        uncertainFields: Set<String> = [],
        scheduleInferred: Bool = false,
        confidence: Confidence = .high
    ) {
        self.name = name
        self.dosage = dosage
        self.form = form
        self.quantity = quantity
        self.timedDoses = times.map { TimedDose(time: $0) }
        self.repeatMode = repeatMode
        self.weekdays = weekdays
        self.intervalDays = intervalDays
        self.anchorDate = anchorDate
        self.daysOfMonth = daysOfMonth
        self.iconName = iconName
        self.colorHex = colorHex
        self.instructions = instructions
        self.durationMode = durationMode
        self.durationDays = durationDays
        self.endDateChoice = endDateChoice
        self.leadTimeMinutes = leadTimeMinutes
        self.refillTrackingOn = refillTrackingOn
        self.refillThresholdDays = refillThresholdDays
        self.unitsPerDose = unitsPerDose
        self.refillNewStock = refillNewStock
        self.isEditingExisting = isEditingExisting
        self.existingUnitsAtRefill = existingUnitsAtRefill
        self.existingRefillDate = existingRefillDate
        self.source = source
        self.uncertainFields = uncertainFields
        self.scheduleInferred = scheduleInferred
        self.confidence = confidence

        // Any field the parser flagged as uncertain is "must review" — matching the server's own
        // `requiresReview` signal (confidence != high, OR any uncertainFields, OR an inferred schedule),
        // so a MEDIUM-confidence draft with an uncertain name/dosage is caught too, not only a low one
        // (AI3). These flags are ACKNOWLEDGEABLE (a correct value can be confirmed without editing); an
        // empty name is enforced separately by `trimmedName`.
        var must = Set<String>()
        if source != .manual {
            // Low overall confidence ALWAYS makes name + dosage must-review, even if the model left
            // `uncertainFields` empty — the prompt only guarantees it sets confidence low when the name or
            // dosage is uncertain, so a low draft must never confirm with zero acknowledgement (A6).
            let low = confidence == .low
            if low || uncertainFields.contains("name") { must.insert("name") }
            if low || uncertainFields.contains("dosage") { must.insert("dosage") }
        }
        // An inferred OR flagged SCHEDULE is also must-review: a wrong cadence is a dosing-safety error
        // and the easiest wrong value to confirm. `scheduleInferred` flags it regardless of overall
        // confidence — an inferred schedule is a guess even on a confidently-parsed drug.
        if source != .manual && (scheduleInferred || uncertainFields.contains("schedule")) {
            must.insert("schedule")
        }
        self.mustEdit = must
    }

    static func empty(at hour: Int = 8, minute: Int = 0, calendar: Calendar = .current) -> EditableDraft {
        EditableDraft(times: [Self.time(hour: hour, minute: minute, calendar: calendar)], source: .manual)
    }

    /// Build from a parser draft (AI/scan). The parser doesn't infer complex repeats, so default
    /// to every day — the user adjusts in the review screen.
    convenience init(from draft: DraftMedication, source: Source, calendar: Calendar = .current) {
        let parsed = draft.schedule.compactMap { Self.parseHHmm($0, calendar: calendar) }
        let times = parsed.isEmpty ? [Self.time(hour: 8, minute: 0, calendar: calendar)] : parsed
        self.init(
            name: draft.name ?? "",
            dosage: draft.dosage ?? "",
            form: draft.form ?? "",
            quantity: draft.quantity ?? "",
            times: times,
            repeatMode: .everyday,
            source: source,
            uncertainFields: Set(draft.uncertainFields),
            scheduleInferred: draft.scheduleInferred,
            confidence: draft.confidence
        )
    }

    /// Prefill from an existing medicine (edit flow). Repeat mode is inferred from the first rule.
    convenience init(editing medicine: Medicine, calendar: Calendar = .current) {
        let doseTimes = medicine.doseTimes.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        let times = doseTimes.map { Self.time(hour: $0.hour, minute: $0.minute, calendar: calendar) }

        var mode: RepeatMode = .everyday
        var weekdays: Set<Int> = []
        var interval = 2
        var anchor: Date?
        var daysOfMonth: Set<Int> = []
        if let first = doseTimes.first {
            if !first.daysOfMonth.isEmpty { mode = .daysOfMonth; daysOfMonth = Set(first.daysOfMonth) }
            else if first.intervalDays >= 2 { mode = .everyNDays; interval = first.intervalDays; anchor = first.anchorDate }
            else if !first.weekdays.isEmpty { mode = .weekdays; weekdays = Set(first.weekdays) }
        }

        self.init(
            name: medicine.name,
            dosage: medicine.dosage ?? "",
            form: medicine.form ?? "",
            quantity: medicine.quantity ?? "",
            times: times.isEmpty ? [Self.time(hour: 8, minute: 0, calendar: calendar)] : times,
            repeatMode: mode,
            weekdays: weekdays,
            intervalDays: interval,
            anchorDate: anchor,
            daysOfMonth: daysOfMonth,
            iconName: medicine.iconName,
            colorHex: medicine.colorHex,
            instructions: medicine.instructions ?? "",
            // Editing shows an existing end as an explicit "until" date (unambiguous); else ongoing.
            durationMode: medicine.endDate != nil ? .until : .ongoing,
            endDateChoice: medicine.endDate ?? .now,
            leadTimeMinutes: medicine.leadTimeMinutes,
            refillTrackingOn: medicine.refillThresholdDays != nil,
            refillThresholdDays: medicine.refillThresholdDays ?? 7,
            unitsPerDose: medicine.unitsPerDose,
            isEditingExisting: true,
            existingUnitsAtRefill: medicine.unitsAtRefill,
            existingRefillDate: medicine.refillDate,
            source: .manual
        )
    }

    // MARK: - Editing / validation

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    func markEdited(_ field: String) { mustEdit.remove(field); acknowledged.remove(field) }

    /// The human is the trust authority: acknowledging a flagged field confirms its value as-is
    /// (deliberate "Looks right" tap), clearing the block without changing the value.
    func acknowledge(_ field: String) { mustEdit.remove(field); acknowledged.insert(field) }
    func wasAcknowledged(_ field: String) -> Bool { acknowledged.contains(field) }

    /// A sensible starting number for the "set current pack count" control (the last baseline, or 30).
    var refillStartingStock: Int { existingUnitsAtRefill ?? 30 }

    /// Confirm is blocked while the name is empty or any must-edit field is still untouched.
    var blocksConfirm: Bool { trimmedName.isEmpty || scheduleIncomplete || !mustEdit.isEmpty }

    /// A chosen repeat mode whose selection is empty — "specific weekdays" or "days of month" with nothing
    /// picked. The engine reads an empty `weekdays`/`daysOfMonth` as EVERY DAY, so confirming this would
    /// silently create a daily schedule; block it until a day is chosen or the mode changes (A1).
    var scheduleIncomplete: Bool {
        switch repeatMode {
        case .weekdays: return weekdays.isEmpty
        case .daysOfMonth: return daysOfMonth.isEmpty
        case .everyday, .everyNDays: return false
        }
    }

    func isUncertain(_ field: String) -> Bool { uncertainFields.contains(field) }
    func mustReview(_ field: String) -> Bool { mustEdit.contains(field) }

    // MARK: - Mapping to the domain model

    func doseTimes(now: Date = .now, calendar: Calendar = .current) -> [DoseTime] {
        // De-dup identical times (e.g. "Add time" seeds a copy of the last picker) so two equal times
        // never persist as two identical DoseTime rules — which would collide as slots and double-count
        // adherence. The engine also de-dups defensively; this keeps the stored data clean at the source.
        var seen = Set<Int>()
        return times.compactMap { time in
            let c = calendar.dateComponents([.hour, .minute], from: time)
            let hour = c.hour ?? 0, minute = c.minute ?? 0
            guard seen.insert(hour * 60 + minute).inserted else { return nil }
            switch repeatMode {
            case .everyday:
                return DoseTime(hour: hour, minute: minute)
            case .weekdays:
                return DoseTime(hour: hour, minute: minute, weekdays: weekdays.sorted())
            case .everyNDays:
                // Keep the cycle's original anchor when editing; only a genuinely new schedule
                // starts its cycle today.
                return DoseTime(hour: hour, minute: minute,
                                intervalDays: max(2, intervalDays),
                                anchorDate: anchorDate ?? calendar.startOfDay(for: now))
            case .daysOfMonth:
                return DoseTime(hour: hour, minute: minute, daysOfMonth: daysOfMonth.sorted())
            }
        }
    }

    /// Apply edited values onto a medicine (used for both new and existing). The caller inserts the
    /// new `DoseTime`s into the context.
    func apply(to medicine: Medicine, newDoseTimes: [DoseTime]) {
        medicine.name = trimmedName
        medicine.dosage = dosage.trimmedNilIfEmpty
        medicine.form = form.trimmedNilIfEmpty
        medicine.quantity = quantity.trimmedNilIfEmpty
        medicine.iconName = iconName
        medicine.colorHex = colorHex
        medicine.instructions = instructions.trimmedNilIfEmpty
        medicine.endDate = resolvedEndDate(start: medicine.createdAt)
        medicine.leadTimeMinutes = leadTimeMinutes
        applyRefill(to: medicine)
        medicine.trustState = .confirmed
        medicine.doseTimes = newDoseTimes
    }

    /// Persist the refill config. Re-baselines the stock (unitsAtRefill/refillDate → now) ONLY when the
    /// user provided a new pack size; otherwise the existing baseline is preserved so an unrelated edit
    /// never resets consumption tracking. Tracking off clears everything.
    private func applyRefill(to medicine: Medicine) {
        guard refillTrackingOn else {
            medicine.unitsAtRefill = nil
            medicine.refillDate = nil
            medicine.refillThresholdDays = nil
            medicine.unitsPerDose = 1
            return
        }
        medicine.refillThresholdDays = max(1, refillThresholdDays)
        medicine.unitsPerDose = max(1, unitsPerDose)
        if let newStock = refillNewStock {
            medicine.unitsAtRefill = max(0, newStock)
            medicine.refillDate = .now
        } else {
            medicine.unitsAtRefill = existingUnitsAtRefill
            medicine.refillDate = existingRefillDate
        }
    }

    /// The treatment end date this draft resolves to (nil = ongoing). "For N days" counts inclusively
    /// from the start day (day 1 = start), so a 10-day course ends on start + 9 days.
    func resolvedEndDate(start: Date, calendar: Calendar = .current) -> Date? {
        switch durationMode {
        case .ongoing:
            return nil
        case .days:
            return calendar.date(byAdding: .day, value: max(1, durationDays) - 1, to: calendar.startOfDay(for: start))
        case .until:
            return calendar.startOfDay(for: endDateChoice)
        }
    }

    // MARK: - Helpers

    private static func time(hour: Int, minute: Int, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    private static func parseHHmm(_ string: String, calendar: Calendar) -> Date? {
        let parts = string.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return time(hour: h, minute: m, calendar: calendar)
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
