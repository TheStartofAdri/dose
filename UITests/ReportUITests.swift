import XCTest

/// Item 1 end-to-end: open the report options from History, generate, and reach the iOS share sheet.
final class ReportUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func attach(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testExportReportFromHistoryReachesShareSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedHistoryDemo", "-tab", "history"]
        app.launch()

        app.buttons["Export report"].tap()
        XCTAssertTrue(app.buttons["generateReport"].waitForExistence(timeout: 10),
                      "the report options screen (med selection + date range) appears")
        attach("report-options")

        app.buttons["generateReport"].tap()
        // The system share sheet (a remote-view activity controller) presents over the options, so
        // the Generate button becomes non-hittable — a reliable in-app signal that sharing started.
        let generate = app.buttons["generateReport"]
        let covered = expectation(for: NSPredicate(format: "hittable == FALSE"), evaluatedWith: generate)
        wait(for: [covered], timeout: 15)
        attach("report-share-sheet")
    }
}
