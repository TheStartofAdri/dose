import XCTest
@testable import Dose

final class DoseActionSheetLogicTests: XCTestCase {
    /// Snooze is offered ONLY for a due / missed / snoozed dose — never for a not-yet-due `.upcoming`
    /// one. FAIL-BEFORE: the sheet offered snooze for any dose, so snoozing an upcoming dose left its
    /// original on-time reminder to re-arm on the next reschedule (a duplicate reminder).
    func testOffersSnoozeOnlyForActionableStatuses() {
        XCTAssertTrue(DoseActionSheet.offersSnooze(for: .due))
        XCTAssertTrue(DoseActionSheet.offersSnooze(for: .missed))
        XCTAssertTrue(DoseActionSheet.offersSnooze(for: .snoozed))
        XCTAssertFalse(DoseActionSheet.offersSnooze(for: .upcoming),
                       "snoozing a not-yet-due dose is disallowed (it would double-arm the reminder)")
        XCTAssertFalse(DoseActionSheet.offersSnooze(for: .taken))
        XCTAssertFalse(DoseActionSheet.offersSnooze(for: .skipped))
    }
}
