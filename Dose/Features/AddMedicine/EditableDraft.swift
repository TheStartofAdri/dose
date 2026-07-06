import Foundation
import SwiftUI

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
    var times: [Date]            // only hour/minute are meaningful

    var repeatMode: RepeatMode
    var weekdays: Set<Int>       // Calendar weekday numbers (1 = Sunday) — repeatMode == .weekdays
    var intervalDays: Int        // repeatMode == .everyNDays (>= 2)
    var daysOfMonth: Set<Int>    // 1...31 — repeatMode == .daysOfMonth

    // Extras (icon/colour, treatment duration, instructions) — edited in the post-save/extras editor.
    var iconName: String?
    var colorHex: String?
    var instructions: String
    var durationMode: DurationMode
    var durationDays: Int        // durationMode == .days (>= 1)
    var endDateChoice: Date      // durationMode == .until
    var leadTimeMinutes: Int?    // optional "remind me N min before" heads-up (nil = none)

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
        daysOfMonth: Set<Int> = [],
        iconName: String? = nil,
        colorHex: String? = nil,
        instructions: String = "",
        durationMode: DurationMode = .ongoing,
        durationDays: Int = 7,
        endDateChoice: Date = .now,
        leadTimeMinutes: Int? = nil,
        source: Source = .manual,
        uncertainFields: Set<String> = [],
        scheduleInferred: Bool = false,
        confidence: Confidence = .high
    ) {
        self.name = name
        self.dosage = dosage
        self.form = form
        self.quantity = quantity
        self.times = times
        self.repeatMode = repeatMode
        self.weekdays = weekdays
        self.intervalDays = intervalDays
        self.daysOfMonth = daysOfMonth
        self.iconName = iconName
        self.colorHex = colorHex
        self.instructions = instructions
        self.durationMode = durationMode
        self.durationDays = durationDays
        self.endDateChoice = endDateChoice
        self.leadTimeMinutes = leadTimeMinutes
        self.source = source
        self.uncertainFields = uncertainFields
        self.scheduleInferred = scheduleInferred
        self.confidence = confidence

        // Only low-confidence flags are "must review" — and those are ACKNOWLEDGEABLE (a correct value
        // can be confirmed without editing). An empty name is enforced separately by `trimmedName`.
        var must = Set<String>()
        if source != .manual && confidence == .low {
            if uncertainFields.contains("name") { must.insert("name") }
            if uncertainFields.contains("dosage") { must.insert("dosage") }
        }
        // An inferred or low-confidence SCHEDULE is also must-review: a wrong cadence is a dosing-safety
        // error, and is otherwise the easiest wrong value to confirm. `scheduleInferred` flags it
        // regardless of overall confidence — an inferred schedule is a guess even on a confidently-parsed
        // drug. Acknowledgeable + editable exactly like name/dosage (no parallel mechanism).
        if source != .manual && (scheduleInferred || (confidence == .low && uncertainFields.contains("schedule"))) {
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
        var daysOfMonth: Set<Int> = []
        if let first = doseTimes.first {
            if !first.daysOfMonth.isEmpty { mode = .daysOfMonth; daysOfMonth = Set(first.daysOfMonth) }
            else if first.intervalDays >= 2 { mode = .everyNDays; interval = first.intervalDays }
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
            daysOfMonth: daysOfMonth,
            iconName: medicine.iconName,
            colorHex: medicine.colorHex,
            instructions: medicine.instructions ?? "",
            // Editing shows an existing end as an explicit "until" date (unambiguous); else ongoing.
            durationMode: medicine.endDate != nil ? .until : .ongoing,
            endDateChoice: medicine.endDate ?? .now,
            leadTimeMinutes: medicine.leadTimeMinutes,
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

    /// Confirm is blocked while the name is empty or any must-edit field is still untouched.
    var blocksConfirm: Bool { trimmedName.isEmpty || !mustEdit.isEmpty }

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
                return DoseTime(hour: hour, minute: minute,
                                intervalDays: max(2, intervalDays), anchorDate: calendar.startOfDay(for: now))
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
        medicine.trustState = .confirmed
        medicine.doseTimes = newDoseTimes
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
