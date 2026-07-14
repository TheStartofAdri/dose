import Foundation
import SwiftData

/// A health metric the user chose to track — a symptom or a vital (v8). The "definition" half, mirroring
/// how `Medicine` defines and `DoseLog` records. Symptoms use a 0–10 severity; vitals use a number + unit.
@Model
final class TrackedMetric {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var valueKindRaw: String
    /// Unit for `.number` vitals (e.g. "kg", "mmHg", "mg/dL"); nil for `.severity` symptoms.
    var unit: String?
    var iconName: String?
    var colorHex: String?
    var isActive: Bool
    var createdAt: Date
    var sortOrder: Int
    /// Log entries — cascade-deleted with the metric (an entry is meaningless without its definition).
    @Relationship(deleteRule: .cascade, inverse: \MetricEntry.metric) var entries: [MetricEntry]

    var kind: MetricKind {
        get { MetricKind(rawValue: kindRaw) ?? .symptom }
        set { kindRaw = newValue.rawValue }
    }
    var valueKind: MetricValueKind {
        get { MetricValueKind(rawValue: valueKindRaw) ?? .severity }
        set { valueKindRaw = newValue.rawValue }
    }

    /// Active metrics in display order — the single filter every metric surface reads.
    static func active(_ metrics: [TrackedMetric]) -> [TrackedMetric] {
        metrics.filter { $0.isActive }.sorted { $0.sortOrder < $1.sortOrder }
    }

    init(id: UUID = UUID(), name: String, kind: MetricKind, valueKind: MetricValueKind,
         unit: String? = nil, iconName: String? = nil, colorHex: String? = nil,
         isActive: Bool = true, createdAt: Date = .now, sortOrder: Int = 0, entries: [MetricEntry] = []) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.valueKindRaw = valueKind.rawValue
        self.unit = unit
        self.iconName = iconName
        self.colorHex = colorHex
        self.isActive = isActive
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.entries = entries
    }
}

/// One logged measurement/observation for a `TrackedMetric` (v8). `severity` (0–10) for symptoms,
/// `value` + the metric's unit for vitals. `source` distinguishes a manual log from a HealthKit sync.
@Model
final class MetricEntry {
    @Attribute(.unique) var id: UUID
    var value: Double?           // for .number vitals
    var severity: Int?           // 0...10 for .severity symptoms
    var note: String?
    var loggedAt: Date
    var sourceRaw: String
    var metric: TrackedMetric?

    var source: MetricSource {
        get { MetricSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), value: Double? = nil, severity: Int? = nil, note: String? = nil,
         loggedAt: Date = .now, source: MetricSource = .manual, metric: TrackedMetric? = nil) {
        self.id = id
        self.value = value
        self.severity = severity
        self.note = note
        self.loggedAt = loggedAt
        self.sourceRaw = source.rawValue
        self.metric = metric
    }

    /// The value formatted for display, honouring the metric's kind (e.g. "6/10", "72.5 kg", "120").
    var displayValue: String {
        if let severity { return "\(severity)/10" }
        guard let value else { return "—" }
        let num = value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        if let unit = metric?.unit, !unit.isEmpty { return "\(num) \(unit)" }
        return num
    }
}

extension TrackedMetric {
    /// The most recent entry by time (for the "same as last time" prefill + the row's latest reading).
    var latestEntry: MetricEntry? { entries.max { $0.loggedAt < $1.loggedAt } }

    /// Whether an entry was logged today — drives Today's "check-ins" prompt.
    func hasEntryToday(now: Date = .now, calendar: Calendar = .current) -> Bool {
        entries.contains { calendar.isDate($0.loggedAt, inSameDayAs: now) }
    }

    /// Recent entries, newest first.
    func recentEntries(limit: Int = 20) -> [MetricEntry] {
        entries.sorted { $0.loggedAt > $1.loggedAt }.prefix(limit).map { $0 }
    }
}

extension MetricEntry {
    /// The numeric value for charting: the vital's value, or a symptom's severity as a Double.
    var chartValue: Double? { value ?? severity.map(Double.init) }
}
