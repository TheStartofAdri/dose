import XCTest
import SwiftData
@testable import Dose

/// Fix 1: a failed store load must be SURFACED, not silently continued. These prove the recovery
/// DECISION (`resolveContainer`) classifies each path and that the notice state is actually triggered
/// — without needing to corrupt a real store (closures simulate the load/migration failure).
final class StoreHealthTests: XCTestCase {
    private struct LoadError: Error {}

    private func memoryContainer() throws -> ModelContainer {
        let schema = DoseStore.currentSchema
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    func testCleanLoadIsNormalAndNeverRecovers() throws {
        var recovered = false
        let (_, outcome) = DoseStore.resolveContainer(
            primary: { try self.memoryContainer() },
            recreate: { XCTFail("recreate must not run on a clean load"); return try self.memoryContainer() },
            inMemory: { XCTFail("inMemory must not run on a clean load"); return try self.memoryContainer() },
            onRecover: { recovered = true }
        )
        XCTAssertEqual(outcome, .normal)
        XCTAssertFalse(recovered, "a clean load never moves the store aside")
    }

    func testFailedLoadSetsAsideAndRecreatesEmptyStore() throws {
        var recoverCount = 0
        let (_, outcome) = DoseStore.resolveContainer(
            primary: { throw LoadError() },
            recreate: { try self.memoryContainer() },
            inMemory: { XCTFail("inMemory must not run when recreate succeeds"); return try self.memoryContainer() },
            onRecover: { recoverCount += 1 }
        )
        XCTAssertEqual(outcome, .recreatedEmptyStore)
        XCTAssertEqual(recoverCount, 1, "the unreadable store is set aside exactly once before recreating")
    }

    func testBothFailuresFallBackToInMemory() throws {
        let (_, outcome) = DoseStore.resolveContainer(
            primary: { throw LoadError() },
            recreate: { throw LoadError() },
            inMemory: { try self.memoryContainer() },
            onRecover: {}
        )
        XCTAssertEqual(outcome, .inMemoryFallback)
    }

    /// The notice state is triggered by a non-normal outcome and suppressed once acknowledged —
    /// proving recovery is surfaced to the UI, not just NSLog'd.
    @MainActor
    func testNeedsNoticeTracksOutcomeAndAcknowledgement() {
        let health = StoreHealth.shared
        health.outcome = .normal
        XCTAssertFalse(health.needsNotice, "a normal load shows no notice")

        health.outcome = .recreatedEmptyStore
        XCTAssertTrue(health.needsNotice, "a recovery surfaces a notice (not just an NSLog)")

        health.acknowledge()
        XCTAssertFalse(health.needsNotice, "acknowledging dismisses the notice for this launch")
    }
}
