import Foundation
import HealthKit
import SwiftData

/// Thin wrapper over `HKHealthStore` for importing vitals into `MetricEntry` and writing the user's
/// manual vitals back. The store interaction is device-only (HealthKit doesn't run in the Simulator);
/// the value mapping it relies on lives in `HealthMetricType` and is unit-tested separately.
@MainActor
final class HealthKitService {
    static let shared = HealthKitService()
    private let store = HKHealthStore()
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private func types(for metrics: [TrackedMetric]) -> Set<HKQuantityType> {
        Set(metrics.compactMap { HealthMetricType.forMetricName($0.name)?.quantityType })
    }

    /// Whether any of these metrics is HealthKit-backed (so we should offer the Connect action).
    func hasSyncableMetrics(_ metrics: [TrackedMetric]) -> Bool { !types(for: metrics).isEmpty }

    /// Request read+write authorization for the HK-backed metrics. Returns whether the request completed
    /// (NOT whether the user granted read — HealthKit never discloses read permission).
    @discardableResult
    func requestAuthorization(for metrics: [TrackedMetric]) async -> Bool {
        guard Self.isAvailable else { return false }
        let ts = types(for: metrics)
        guard !ts.isEmpty else { return false }
        do { try await store.requestAuthorization(toShare: ts, read: ts); return true }
        catch { return false }
    }

    /// Import samples for each HK-backed metric over the last `days` days as `MetricEntry(source:
    /// .healthKit)`, skipping any already present (de-duped by metric + timestamp). Returns imported count.
    @discardableResult
    func importRecent(for metrics: [TrackedMetric], days: Int = 30, now: Date = .now,
                      into context: ModelContext) async -> Int {
        guard Self.isAvailable else { return 0 }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        var imported = 0
        for metric in metrics {
            guard let hk = HealthMetricType.forMetricName(metric.name), let qt = hk.quantityType else { continue }
            let existing = metric.entries.map { ($0.loggedAt, $0.source) }
            for sample in await samples(of: qt, from: start, to: now) {
                guard Self.shouldImport(sampleStart: sample.startDate, existing: existing) else { continue }
                let value = hk.appValue(fromHKValue: sample.quantity.doubleValue(for: hk.hkUnit))
                context.insert(MetricEntry(value: value, loggedAt: sample.startDate, source: .healthKit, metric: metric))
                imported += 1
            }
        }
        if imported > 0 { try? context.save() }
        return imported
    }

    /// Whether a HealthKit sample at `sampleStart` should be imported. De-dup is scoped to EXISTING
    /// HealthKit-sourced entries only (within 1s), so a manual entry never suppresses a real HK sample
    /// (and vice-versa) and a re-import stays idempotent. Pure + unit-testable.
    static func shouldImport(sampleStart: Date, existing: [(loggedAt: Date, source: MetricSource)]) -> Bool {
        !existing.contains { $0.source == .healthKit && abs($0.loggedAt.timeIntervalSince(sampleStart)) < 1 }
    }

    private func samples(of type: HKQuantityType, from: Date, to: Date) async -> [HKQuantitySample] {
        await withCheckedContinuation { continuation in
            // Exclude the app's OWN write-backs so a manually-logged vital we saved to Health isn't
            // re-imported as a duplicate HK entry.
            let inRange = HKQuery.predicateForSamples(withStart: from, end: to)
            let notOurs = NSCompoundPredicate(notPredicateWithSubpredicate:
                HKQuery.predicateForObjects(from: HKSource.default()))
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [inRange, notOurs])
            // DESCENDING + limit 100 → keep the 100 MOST RECENT samples (ascending previously kept the
            // oldest 100, dropping recent data — the opposite of "importRecent").
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 100,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, results, _ in
                continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }

    /// Write a manually-logged vital back to HealthKit (best-effort — silent on failure / no permission).
    func writeSample(for metric: TrackedMetric, value: Double, at: Date = .now) async {
        guard Self.isAvailable,
              let hk = HealthMetricType.forMetricName(metric.name), let qt = hk.quantityType else { return }
        let quantity = HKQuantity(unit: hk.hkUnit, doubleValue: hk.hkValue(fromAppValue: value))
        try? await store.save(HKQuantitySample(type: qt, quantity: quantity, start: at, end: at))
    }
}
