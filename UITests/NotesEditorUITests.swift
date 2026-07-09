import XCTest

/// Item 1: a note can be used as a note. Writing one and tapping Done saves it and exits without
/// any analysis/parse — Analyze stays a separate, optional action.
final class NotesEditorUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testWriteNoteAndDonePersistsWithoutAnalyzing() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-stubParser", "-uiTestReset", "-tab", "notes"]
        app.launch()

        app.buttons["Add note"].tap()
        let field = app.textFields["Write a note…"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Buy more vitamin D")

        // Done saves and exits — no parse/review.
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["Buy more vitamin D"].waitForExistence(timeout: 5),
                      "Done saves the note and returns to the list")
        XCTAssertFalse(app.buttons["Confirm"].exists, "Done must not trigger analysis/review")
    }

    // Item 5 — the whole note row is the tap target (not just the text/subtitle).
    func testNoteRowTrailingAreaOpensNote() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedHistoryDemo", "-tab", "notes"]
        app.launch()

        let cell = app.cells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        // Tap the far-right of the row — only reachable if the whole row is the tap target.
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5),
                      "tapping the row's trailing area opens the note editor")
    }

    // Phase 7: a note can be tagged, and the tag filter chips show / hide it accordingly.
    func testTagFilterShowsAndHidesNotes() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-stubParser", "-uiTestReset", "-tab", "notes"]
        app.launch()

        app.buttons["Add note"].tap()
        let field = app.textFields["Write a note…"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Felt dizzy this morning")
        app.buttons["Symptoms tag"].tap()          // tag it "Symptoms" in the editor
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["Felt dizzy this morning"].waitForExistence(timeout: 5),
                      "the tagged note is in the list")
        // Filter by a DIFFERENT tag → hidden.
        app.buttons["Side Effects"].tap()
        XCTAssertFalse(app.staticTexts["Felt dizzy this morning"].exists,
                       "a Symptoms note is hidden under the Side Effects filter")
        // Filter by its OWN tag → shown again.
        app.buttons["Symptoms"].tap()
        XCTAssertTrue(app.staticTexts["Felt dizzy this morning"].waitForExistence(timeout: 5),
                      "the note shows under its own tag filter")
    }

    // Item 5 — a blank note isn't persisted.
    func testBlankNoteIsDiscarded() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-uiTestReset", "-tab", "notes"]
        app.launch()

        app.buttons["Add note"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()   // back without typing

        XCTAssertTrue(app.staticTexts["No notes yet"].waitForExistence(timeout: 5),
                      "a note left blank is removed, not persisted as an empty row")
    }
}
