import XCTest
@testable import Dose

/// The HealthKit import de-dup rule (device-only import itself isn't unit-testable, but the pure rule
/// is). Confirmed bug it fixes: the old timestamp-only de-dup matched MANUAL entries, so a manual log
/// within 1s silently suppressed a real HealthKit sample.
@MainActor
final class HealthKitDedupTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_800_000_000)

    func testManualEntryDoesNotSuppressHKSample() {
        XCTAssertTrue(HealthKitService.shouldImport(sampleStart: t, existing: [(t, .manual)]),
                      "a manual entry at the same time must NOT block a real HealthKit sample")
    }

    func testExistingHKEntryDedupsReimport() {
        XCTAssertFalse(HealthKitService.shouldImport(sampleStart: t, existing: [(t, .healthKit)]),
                       "re-importing the same HK sample is idempotent (deduped against the HK-sourced entry)")
    }

    func testDistinctTimesBothImport() {
        XCTAssertTrue(HealthKitService.shouldImport(sampleStart: t.addingTimeInterval(5), existing: [(t, .healthKit)]),
                      "a HK sample 5s from an existing HK entry is a distinct reading — imported")
    }

    func testEmptyExistingImports() {
        XCTAssertTrue(HealthKitService.shouldImport(sampleStart: t, existing: []))
    }
}
