import Foundation
import SwiftData

/// A recurring **rule** for when a dose is due — nothing more. It carries no status; whether a
/// dose was taken/skipped/missed is derived at read time from `DoseLog`.
///
/// Repeat patterns (precedence: days-of-month → every-N-days → weekdays → daily):
/// - `weekdays` empty AND `intervalDays < 2` AND `daysOfMonth` empty → **every day**.
/// - `weekdays` non-empty → **specific weekdays** (Calendar weekday numbers, 1 = Sunday).
/// - `intervalDays >= 2` with `anchorDate` → **every N days** from the anchor.
/// - `daysOfMonth` non-empty → **specific days of the month** (1...31).
@Model
final class DoseTime {
    var hour: Int
    var minute: Int
    var weekdays: [Int] = []
    // New in v2 — defaults make them migration-safe so existing (v1) rows get valid values rather
    // than crashing in-place migration (Code=134110, missing mandatory attribute value).
    var intervalDays: Int = 0
    var anchorDate: Date?
    var daysOfMonth: [Int] = []
    var medicine: Medicine?

    init(
        hour: Int,
        minute: Int,
        weekdays: [Int] = [],
        intervalDays: Int = 0,
        anchorDate: Date? = nil,
        daysOfMonth: [Int] = [],
        medicine: Medicine? = nil
    ) {
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.intervalDays = intervalDays
        self.anchorDate = anchorDate
        self.daysOfMonth = daysOfMonth
        self.medicine = medicine
    }

    /// Value-type rule mirroring this @Model (the single source of truth for date matching).
    var rule: DoseSlotRule {
        DoseSlotRule(hour: hour, minute: minute, weekdays: weekdays,
                     intervalDays: intervalDays, anchorDate: anchorDate, daysOfMonth: daysOfMonth)
    }

    func applies(on day: Date, calendar: Calendar = .current) -> Bool {
        rule.applies(on: day, calendar: calendar)
    }

    func scheduledDate(on day: Date, calendar: Calendar = .current) -> Date? {
        rule.scheduledDate(on: day, calendar: calendar)
    }
}
