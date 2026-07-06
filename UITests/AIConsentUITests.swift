import XCTest

/// Apple 5.1.2(i) (Nov 2025): before the first AI parse sends anything off-device, the app must get
/// explicit consent. With consent reset (`-resetAIConsent`), invoking note-analyze must surface the
/// "Use AI to read this?" prompt BEFORE any parse/review; tapping Continue then proceeds into the
/// (stubbed) review gate. `-skipAuth` premium-grants, so the premium gate isn't what's blocking here.
final class AIConsentUITests: XCTestCase {
    func testFirstAIUseShowsConsentThenProceeds() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-stubParser", "-seedHistoryDemo", "-tab", "notes", "-resetAIConsent"]
        app.launch()

        let note = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ibuprofen")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10)); note.tap()
        app.buttons["analyzeNote"].tap()

        // The one-time consent must appear BEFORE anything is parsed or reviewed.
        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5),
                      "first AI use shows the explicit consent prompt")
        XCTAssertFalse(app.buttons["Confirm"].exists, "nothing is parsed/reviewed before consent")

        continueButton.tap()
        XCTAssertTrue(app.buttons["Confirm"].waitForExistence(timeout: 10),
                      "after consent, the stubbed analysis lands in the review gate")
    }
}
