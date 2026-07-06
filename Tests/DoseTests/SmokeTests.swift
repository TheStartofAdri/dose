import XCTest
@testable import Dose

/// Sanity checks that the model layer compiles and behaves. Replaced/expanded by the engine and
/// streak suites in step 2.
final class SmokeTests: XCTestCase {
    func testDraftMedicationDefaults() {
        let draft = DraftMedication(name: "Vitamin D")
        XCTAssertEqual(draft.name, "Vitamin D")
        XCTAssertTrue(draft.schedule.isEmpty)
        XCTAssertEqual(draft.confidence, .low)
        XCTAssertTrue(draft.requiresReview)
    }

    func testMedicineDefaultsToDraftTrustState() {
        let med = Medicine(name: "Antibiotic")
        XCTAssertEqual(med.trustState, .draft)
        XCTAssertTrue(med.isActive)
    }

    func testDoseTimeAppliesEveryDayWhenWeekdaysEmpty() {
        let dt = DoseTime(hour: 8, minute: 0)
        XCTAssertTrue(dt.applies(on: .now))
    }
}
