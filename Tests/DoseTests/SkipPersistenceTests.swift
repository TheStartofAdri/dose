import XCTest
import SwiftData
@testable import Dose

/// Item 2: skip must persist to the OBSERVED (main) context so History/Today reflect it without a
/// reload. Includes a probe to establish SwiftData's cross-context behavior, the positive
/// integration test on the main context, and the detached-context comparison that proves the
/// integration test exercises the gap.
final class SkipPersistenceTests: XCTestCase {
    @MainActor
    private func freshContainer() throws -> ModelContainer {
        try ModelContainer(for: Medicine.self, DoseTime.self, DoseLog.self, Note.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// PROBE (diagnostic): after a detached `ModelContext(container)` saves, does a fresh
    /// `mainContext.fetch` see it? Result drives how the fail-on-detached test must be written.
    @MainActor
    func testProbeDetachedSaveVisibilityToMainFetch() throws {
        let container = try freshContainer()
        let main = container.mainContext
        let detached = ModelContext(container)
        detached.insert(DoseLog(medicineID: UUID(), medicineName: "X", scheduledFor: .now, action: .skipped))
        try detached.save()
        let count = try main.fetch(FetchDescriptor<DoseLog>()).count
        print("PROBE detached-save → main.fetch count = \(count)")
    }

    /// Positive integration: skip through the real seam on the main context → re-query History from
    /// the SAME context (no reload) → the skip is present and adherence counts it.
    @MainActor
    func testSkipOnMainContextImmediatelyVisible() throws {
        let container = try freshContainer()
        let main = container.mainContext
        let cal = Calendar.current
        let med = Medicine(name: "Heart Med", trustState: .confirmed,
                           createdAt: cal.date(byAdding: .day, value: -2, to: .now)!)
        med.doseTimes = [DoseTime(hour: 8, minute: 0)]
        main.insert(med)
        try main.save()
        let slot = cal.date(bySettingHour: 8, minute: 0, second: 0,
                            of: cal.date(byAdding: .day, value: -1, to: .now)!)!

        try DoseActionWriter.record(.skipped, medicineID: med.id, medicineName: med.name, dosage: nil,
                                    scheduledFor: slot, into: main)

        let logs = try main.fetch(FetchDescriptor<DoseLog>())
        XCTAssertTrue(logs.contains { $0.action == .skipped && ExecutionEngine.sameSlot($0.scheduledFor, slot) },
                      "the skip log is on the observed context")
        let series = AdherenceCalculator.days(
            medicines: try main.fetch(FetchDescriptor<Medicine>()).map { $0.snapshot() },
            logs: logs.map { $0.snapshot() }, now: .now, days: 7)
        XCTAssertEqual(series.reduce(0) { $0 + $1.skipped }, 1)
    }

    /// REGRESSION GUARD for the notification skip path. Because a fresh `main.fetch` sees writes from
    /// any context (see the probe), the deterministic signal is *which context the log belongs to*:
    /// it must be the OBSERVED `container.mainContext`. If the handler wrote to a detached
    /// `ModelContext(container)` — the original bug — `log.modelContext` would be that detached
    /// context and this identity check FAILS; with the `mainContext` fix it PASSES.
    @MainActor
    func testNotificationSkipWritesToObservedContext() throws {
        let container = try freshContainer()
        let handler = NotificationActionHandler(container: container)
        let slot = Date(timeIntervalSince1970: 1_700_000_000)

        let written = try XCTUnwrap(handler.handleAction(
            NotificationScheduler.skipAction, medicineID: UUID(), name: "Heart Med",
            dosage: nil, scheduledFor: slot))

        XCTAssertEqual(written.action, .skipped, "notification 'Skip today' writes a .skipped DoseLog")
        XCTAssertTrue(written.modelContext === container.mainContext,
                      "the skip must be written to the OBSERVED context so a live @Query updates")
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<DoseLog>())
            .filter { $0.action == .skipped }.count, 1)
    }

    /// C2: a save failure must PROPAGATE (not be swallowed and reported as success), and the just-
    /// inserted log must be cleaned up so no phantom row lingers in the observed context.
    /// FAIL-BEFORE: `record` swallowed the error and returned the log — no throw, and the phantom insert
    /// stayed. PASS-AFTER: it throws and leaves the context empty.
    @MainActor
    func testRecordThrowsAndLeavesNoPhantomOnSaveFailure() throws {
        let container = try freshContainer()
        let main = container.mainContext
        DoseActionWriter.forceSaveFailureForTesting = true
        defer { DoseActionWriter.forceSaveFailureForTesting = false }

        XCTAssertThrowsError(
            try DoseActionWriter.record(.taken, medicineID: UUID(), medicineName: "X", dosage: nil,
                                        scheduledFor: .now, into: main),
            "a failed save must propagate, not read as success")
        XCTAssertTrue(try main.fetch(FetchDescriptor<DoseLog>()).isEmpty,
                      "the unsaved phantom log is removed after a failed save")
    }
}
