import XCTest

/// The startup AI-backend reachability guard must surface an unreachable server in Settings at LAUNCH —
/// not only when the user taps Generate/Analyze. `-stubAIBackendUnreachable` forces the flag without a
/// real dead host; the live probe is skipped under -skipAuth, so this is deterministic and offline-safe.
final class AIBackendHealthUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testUnreachableBackendShowsNoticeInSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-tab", "settings", "-uiTestReset", "-stubAIBackendUnreachable"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "Settings is shown")

        // The AI section sits below the fold; scroll until the notice comes into view.
        let notice = app.staticTexts["AI features are unavailable"]
        var tries = 0
        while !notice.exists && tries < 10 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(notice.waitForExistence(timeout: 5),
                      "an unreachable AI backend must surface a notice in Settings at launch")
    }

    /// The complement: with no stub and the live probe skipped (-skipAuth), the notice must NOT appear —
    /// so a healthy launch shows nothing (guards against a banner that's stuck on).
    func testHealthyLaunchShowsNoNotice() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-tab", "settings", "-uiTestReset"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "Settings is shown")
        var tries = 0
        while tries < 10 { app.swipeUp(); tries += 1 }   // scroll through the whole form
        XCTAssertFalse(app.staticTexts["AI features are unavailable"].exists,
                       "no unreachable notice should show when the backend hasn't been flagged")
    }
}
