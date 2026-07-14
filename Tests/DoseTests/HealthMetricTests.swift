import XCTest
import SwiftData
@testable import Dose

/// Phase 2 (symptom/vitals): the new `TrackedMetric` + `MetricEntry` persist under the current (V8)
/// schema, entries cascade with their metric, and the active filter sorts/filters correctly.
@MainActor
final class HealthMetricTests: XCTestCase {
    /// Return the CONTAINER (not just the context) so the test holds it alive — a discarded container
    /// deallocates and tears the store down mid-test.
    private func makeContainer() throws -> ModelContainer {
        let schema = DoseStore.currentSchema
        return try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    func testMetricAndEntriesPersistAndCascadeDelete() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let metric = TrackedMetric(name: "Pain", kind: .symptom, valueKind: .severity)
        ctx.insert(metric)
        ctx.insert(MetricEntry(severity: 6, metric: metric))
        ctx.insert(MetricEntry(severity: 3, metric: metric))
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MetricEntry>()).count, 2)
        XCTAssertEqual(metric.entries.count, 2)

        ctx.delete(metric)
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<TrackedMetric>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MetricEntry>()).count, 0, "entries cascade with the metric")
    }

    func testVitalEntryStoresValueAndUnit() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let weight = TrackedMetric(name: "Weight", kind: .vital, valueKind: .number, unit: "kg")
        ctx.insert(weight)
        ctx.insert(MetricEntry(value: 72.5, metric: weight))
        try ctx.save()
        let entry = try XCTUnwrap(try ctx.fetch(FetchDescriptor<MetricEntry>()).first)
        XCTAssertEqual(entry.value, 72.5)
        XCTAssertEqual(entry.metric?.unit, "kg")
        XCTAssertEqual(entry.source, .manual)
    }

    func testActiveFilterSortsAndDropsInactive() {
        let a = TrackedMetric(name: "B", kind: .vital, valueKind: .number, sortOrder: 2)
        let b = TrackedMetric(name: "A", kind: .symptom, valueKind: .severity, sortOrder: 1)
        let c = TrackedMetric(name: "C", kind: .vital, valueKind: .number, isActive: false, sortOrder: 0)
        XCTAssertEqual(TrackedMetric.active([a, b, c]).map(\.name), ["A", "B"], "active only, sorted by sortOrder")
    }
}
