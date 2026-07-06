import XCTest

/// Item 5 end-to-end (with the DEBUG stub parser, no network): a note is analyzed only on an
/// explicit tap, the draft lands in the mandatory review gate, and confirming creates the medicine.
final class NotesAnalyzeUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testAnalyzeNoteThenConfirmCreatesMedicine() {
        let app = XCUIApplication()
        // Use the seeded note (no keyboard typing) so the test is deterministic; it mentions ibuprofen.
        app.launchArguments = ["-skipAuth", "-stubParser", "-seedHistoryDemo", "-tab", "notes"]
        app.launch()

        let note = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ibuprofen")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        note.tap()

        let analyze = app.buttons["analyzeNote"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        analyze.tap()

        // Mandatory review gate (never auto-saved). The stub infers the schedule, so the times must be
        // acknowledged (or edited) before Confirm enables — a guessed cadence can't be confirmed by inertia.
        let confirm = app.buttons["Confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "the analyzed draft must land in review")
        // The schedule affordance is below the fold — scroll until it's hittable, then acknowledge.
        let looksRight = app.buttons["Looks right"].firstMatch
        XCTAssertTrue(looksRight.waitForExistence(timeout: 5), "an inferred schedule must be acknowledged")
        var tries = 0
        while !looksRight.isHittable && tries < 6 { app.swipeUp(); tries += 1 }
        looksRight.tap()
        confirm.tap()

        // Item 3: a single confirmed med routes into the post-save "almost done" extras step.
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10),
                      "confirming from a note must reach the post-save extras step")
        skip.tap()

        // The medicine now exists — visible on Today (stub yields "Ibuprofen").
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Ibuprofen"].waitForExistence(timeout: 10),
                      "confirming review creates the medicine")
    }
}
