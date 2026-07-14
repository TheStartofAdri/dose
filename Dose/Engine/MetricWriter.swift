import Foundation
import SwiftData
import os

/// The single place a `TrackedMetric` or `MetricEntry` is written — like `DoseActionWriter` for doses.
/// Throws on a save failure (never a silent success) so the UI can surface it.
@MainActor
enum MetricWriter {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.thestartofadri.dose",
                                       category: "metrics")

    @discardableResult
    static func createMetric(name: String, kind: MetricKind, valueKind: MetricValueKind, unit: String?,
                             iconName: String?, colorHex: String?, into context: ModelContext,
                             existing: [TrackedMetric] = []) throws -> TrackedMetric {
        let order = (existing.map(\.sortOrder).max() ?? -1) + 1
        let metric = TrackedMetric(name: name.trimmingCharacters(in: .whitespaces), kind: kind,
                                   valueKind: valueKind, unit: cleaned(unit),
                                   iconName: iconName, colorHex: colorHex, sortOrder: order)
        context.insert(metric)
        try save(context)
        return metric
    }

    @discardableResult
    static func log(_ metric: TrackedMetric, value: Double? = nil, severity: Int? = nil,
                    note: String? = nil, source: MetricSource = .manual, at: Date = .now,
                    into context: ModelContext) throws -> MetricEntry {
        let entry = MetricEntry(value: value, severity: severity, note: cleaned(note),
                                loggedAt: at, source: source, metric: metric)
        context.insert(entry)
        try save(context)
        return entry
    }

    private static func cleaned(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private static func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            logger.error("Failed to save metric change: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}
