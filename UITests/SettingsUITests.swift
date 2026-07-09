import XCTest

/// Settings smoke test. There's no manual "Scan language" picker, and the Scanning copy sets
/// honest expectations (English works best; other languages may not read correctly) rather than
/// promising automatic multilingual recognition (item 5).
final class SettingsUITests: XCTestCase {
    // Phase 8: Settings surfaces a premium PDF-export shortcut (with a PRO badge).
    func testSettingsShowsPremiumExportShortcut() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-tab", "settings"]
        app.launch()
        let export = app.buttons["exportReportRow"]
        var tries = 0
        while !export.exists && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(export.waitForExistence(timeout: 5), "Settings offers a PDF export shortcut")
    }

    override func setUp() { continueAfterFailure = false }

    func testScanningCopyIsHonestAndNoLanguagePicker() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-tab", "settings", "-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "Settings is shown")
        // The Scanning section sits below the fold (Settings grew a Subscription section); scroll to it.
        let copy = app.staticTexts["Scanning works best with English labels."]
        var tries = 0
        while !copy.exists && tries < 8 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(copy.waitForExistence(timeout: 5),
                      "honest, English-first scan copy should be shown")
        // It must not promise automatic multilingual recognition anymore.
        XCTAssertFalse(app.staticTexts["Label scanning reads English and Russian automatically."].exists,
                       "the old 'automatic' multilingual promise must be gone")
        // The old manual picker must be gone.
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Scan language")).firstMatch
        XCTAssertFalse(picker.exists, "the manual Scan language picker should be removed")
    }
}
