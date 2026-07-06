import XCTest

/// End-to-end interactive verification of the core free-tier loop:
/// add a medicine manually → it saves straight to Today (no redundant Review screen) → TAKE marks
/// it taken. (Item 2: manual entry skips the Review gate; that gate is reserved for AI/scan drafts.)
final class AddFlowUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testManualAddGoesStraightToTodayAndTake() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-uiTestReset"]   // start from a clean, empty state
        app.launch()

        // Empty state → start adding.
        let add = app.buttons["Add medicine"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Add medicine entry point should exist")
        add.tap()

        // Method chooser → Manual entry.
        let manual = app.staticTexts["Manual entry"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap()

        // The manual form must start with an EMPTY name (no stray autofill / "At" prefill). An empty
        // TextField reports its placeholder ("Required") as its value.
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Required",
                       "the Name field starts empty (shows only its placeholder)")
        name.tap()
        name.typeText("Test Med")

        // No Review step: there is no "Continue"/"Confirm"; the primary button saves directly.
        XCTAssertFalse(app.buttons["Continue"].exists, "manual entry must not route through Review")
        let save = app.buttons["manualSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        // Manual save offers an optional post-save extras step (not a Review gate) — skip it.
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "manual save shows the optional extras step")
        skip.tap()

        // Back on Today: the dose card appears (default 08:00 daily → due/missed today with TAKE).
        XCTAssertTrue(app.staticTexts["Test Med"].waitForExistence(timeout: 5),
                      "Saved medicine should appear on Today")

        // Execute the dose — no confirmation dialog, just TAKE.
        let take = app.buttons["Take Test Med"]
        XCTAssertTrue(take.waitForExistence(timeout: 5))
        take.tap()

        // It settles to taken: the Take control is replaced by the reversible Undo control.
        XCTAssertTrue(app.buttons["Undo Taken for Test Med"].waitForExistence(timeout: 5),
                      "Dose should settle to taken (and offer Undo) after Take")
        XCTAssertFalse(app.buttons["Take Test Med"].exists, "Take should be gone once taken")
    }
}
