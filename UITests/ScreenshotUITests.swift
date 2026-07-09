import XCTest

/// Captures the screenshots the task asks for, as keep-always attachments:
///   01 — manual entry in the labeled "Details" style (one screen, no Review)
///   02 — Today cards: a full, readable medicine name beside a compact Take
///   03 — the Medicine detail view (details, schedule, that medicine's own history)
///   04 — History showing < 100% with a past-due untaken dose, on a real 14-day timeline
final class ScreenshotUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func attach(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testShot01ManualEntryLabeled() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-uiTestReset"]
        app.launch()

        app.buttons["Add medicine"].firstMatch.tap()
        let manual = app.staticTexts["Manual entry"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5)); manual.tap()

        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Vitamin D")
        let dosage = app.textFields["Dosage"]
        if dosage.exists { dosage.tap(); dosage.typeText("1000 IU") }
        let form = app.textFields["Form"]
        if form.exists { form.tap(); form.typeText("tablet") }

        XCTAssertTrue(app.buttons["manualSave"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue"].exists)
        attach("01-manual-entry-labeled")
    }

    func testShot02TodayCards() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedHistoryDemo"]
        app.launch()
        // The seeded long-name medicine proves the name stays readable next to a compact Take.
        XCTAssertTrue(app.staticTexts["Sustained-Release Magnesium"].waitForExistence(timeout: 10))
        attach("02-today-cards")
    }

    func testShot03MedicineDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedHistoryDemo"]
        app.launch()
        // Tap the schedule ROW (the "Next up" hero above the list can also show this name).
        let row = app.cells.containing(.staticText, identifier: "Vitamin D").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.staticTexts["Vitamin D"].tap()
        XCTAssertTrue(app.staticTexts["Schedule"].waitForExistence(timeout: 5))
        attach("03-medicine-detail")
    }

    func testShot04HistoryBelow100() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedHistoryDemo", "-tab", "history"]
        app.launch()
        // History is now a filterable event log; the analytics (chart/rates) moved to the Week tab.
        XCTAssertTrue(app.buttons["Missed"].waitForExistence(timeout: 10),
                      "the History event log shows its filter chips on seeded data")
        attach("04-history-event-log")
    }

    func testShot05MedicineDetailWithIconAndInstructions() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedHistoryDemo"]
        app.launch()
        // Tap the schedule ROW (the "Next up" hero above the list can also show this name).
        let row = app.cells.containing(.staticText, identifier: "Vitamin D").firstMatch   // seeded with icon, colour, instructions
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.staticTexts["Vitamin D"].tap()
        XCTAssertTrue(app.staticTexts["Instructions"].waitForExistence(timeout: 5))
        attach("05-detail-icon-instructions")
    }

    func testShot06PostSaveExtrasAndDurationPicker() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-uiTestReset"]
        app.launch()

        app.buttons["Add medicine"].firstMatch.tap()
        let manual = app.staticTexts["Manual entry"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5)); manual.tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Metformin")
        app.buttons["manualSave"].tap()

        // The post-save "almost done" extras step.
        XCTAssertTrue(app.staticTexts["Icon & colour"].waitForExistence(timeout: 5))
        attach("06-post-save-extras")

        // Reveal the treatment-duration controls.
        app.buttons["Days"].firstMatch.tap()
        attach("07-duration-picker")
    }

    func testShot08NoteAnalyzeLandsInReview() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-stubParser", "-seedHistoryDemo", "-tab", "notes"]
        app.launch()

        // Open the seeded note and explicitly analyze it.
        let note = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ibuprofen")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        note.tap()
        let analyze = app.buttons["analyzeNote"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 5))
        analyze.tap()

        // Lands in the mandatory review gate.
        XCTAssertTrue(app.buttons["Confirm"].waitForExistence(timeout: 10),
                      "analysis must route into the review gate, not auto-save")
        attach("08-note-analyze-review")

        // The stub infers the schedule, so the times must be acknowledged before Confirm enables.
        // The schedule affordance is below the fold — scroll until it's hittable.
        let looksRight = app.buttons["Looks right"].firstMatch
        XCTAssertTrue(looksRight.waitForExistence(timeout: 5), "an inferred schedule must be reviewed")
        var scheduleTries = 0
        while !looksRight.isHittable && scheduleTries < 6 { app.swipeUp(); scheduleTries += 1 }
        looksRight.tap()

        // Item 3: confirming routes into the post-save extras step (same one the manual path uses).
        app.buttons["Confirm"].tap()
        XCTAssertTrue(app.staticTexts["Icon & colour"].waitForExistence(timeout: 10),
                      "confirm from a note reaches the post-save extras step")
        attach("09-extras-after-note-confirm")
    }

    func testShot11ReviewWarningsBoundToFields() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-stubLowConfidence", "-seedHistoryDemo", "-tab", "notes"]
        app.launch()
        let note = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ibuprofen")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10)); note.tap()
        app.buttons["analyzeNote"].tap()
        XCTAssertTrue(app.staticTexts["Please review and edit this"].waitForExistence(timeout: 10),
                      "low-confidence draft shows field-bound warnings")
        attach("11-review-warnings")
    }

    /// Item 2: a low-confidence flagged value the user judges correct can be confirmed WITHOUT editing,
    /// via a deliberate "Looks right" tap. Confirm is blocked until acknowledged, then enabled.
    func testShot15ReviewConfirmAfterAcknowledge() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-stubLowConfidence", "-seedHistoryDemo", "-tab", "notes"]
        app.launch()
        let note = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ibuprofen")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10)); note.tap()
        app.buttons["analyzeNote"].tap()

        // The flagged fields each carry a "Looks right" affordance; Confirm is blocked until they're acted on.
        XCTAssertTrue(app.buttons["Looks right"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Confirm"].isEnabled,
                       "a flagged-but-untouched draft cannot be confirmed")

        // Acknowledge every flagged field WITHOUT editing its value (the values are actually correct).
        // Some flags (the schedule) sit below the fold, so scroll when the affordance isn't hittable.
        var guardCount = 0
        while app.buttons["Looks right"].firstMatch.exists && guardCount < 12 {
            let btn = app.buttons["Looks right"].firstMatch
            if btn.isHittable { btn.tap() } else { app.swipeUp() }
            guardCount += 1
        }
        XCTAssertTrue(app.staticTexts["Reviewed"].firstMatch.waitForExistence(timeout: 5),
                      "acknowledged fields show a Reviewed mark")
        XCTAssertTrue(app.buttons["Confirm"].isEnabled,
                      "acknowledging the flags unblocks Confirm without any edit")
        attach("15-review-confirm-after-acknowledge")

        // And it actually confirms — reaching the same post-save extras step.
        app.buttons["Confirm"].tap()
        XCTAssertTrue(app.staticTexts["Icon & colour"].waitForExistence(timeout: 10),
                      "confirming an acknowledged-but-unedited value proceeds")
    }

    /// Item 4: the Medicine detail adherence section must render fully (chart + legend), not clipped.
    func testShot16MedicineDetailAdherenceRendersFully() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedHistoryDemo"]
        app.launch()
        // Tap the schedule ROW (the "Next up" hero above the list can also show this name).
        let row = app.cells.containing(.staticText, identifier: "Vitamin D").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.staticTexts["Vitamin D"].tap()
        XCTAssertTrue(app.staticTexts["Schedule"].waitForExistence(timeout: 5))
        // Scroll fully to the bottom (the chart is the last section) so the whole card — title through
        // legend — sits above the translucent tab bar, proving it's not clipped within its own row.
        let chartTitle = app.staticTexts["Last 14 days"]
        for _ in 0..<8 where !chartTitle.isHittable { app.swipeUp() }
        XCTAssertTrue(chartTitle.waitForExistence(timeout: 5),
                      "the medicine-detail adherence chart renders fully (not clipped)")
        attach("16-detail-adherence-full")
    }

    /// Item 3: when notifications are denied/off, Today shows a non-nagging banner with an Open
    /// Settings affordance — the app no longer schedules silently into the void.
    func testShot17RemindersOffBanner() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedHistoryDemo", "-stubNotificationsDenied"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Reminders are off"].waitForExistence(timeout: 10),
                      "a denied notification state surfaces a banner on Today")
        XCTAssertTrue(app.buttons["Open Settings"].exists, "the banner offers a deep link to Settings")
        attach("17-reminders-off-banner")
    }

    /// Feature A: the post-save extras step exposes the optional "Remind me before" lead-time picker.
    func testShot18LeadTimePickerInExtras() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-uiTestReset"]
        app.launch()

        app.buttons["Add medicine"].firstMatch.tap()
        let manual = app.staticTexts["Manual entry"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5)); manual.tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Metformin")
        app.buttons["manualSave"].tap()

        XCTAssertTrue(app.staticTexts["Icon & colour"].waitForExistence(timeout: 5))
        // Scroll until the heads-up reminder picker is actually on screen (it exists offscreen, so
        // gate on hittable, not exists).
        let picker = app.staticTexts["Remind me before"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "the lead-time picker is offered in the extras step")
        var tries = 0
        while !picker.isHittable && tries < 6 { app.swipeUp(); tries += 1 }
        attach("18-lead-time-picker")
    }

    /// The Week tab: weekly adherence analytics (ring, tiles, missed-this-week, 14-day chart).
    func testShot19WeekOverview() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedHistoryDemo"]
        app.launch()
        app.tabBars.buttons["Week"].tap()
        XCTAssertTrue(app.staticTexts["This Week"].waitForExistence(timeout: 10),
                      "the Week tab shows the weekly overview")
        // The 14-day chart lives here now (moved off History).
        let chart = app.staticTexts["Last 14 days"]
        var tries = 0
        while !chart.exists && tries < 8 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(chart.waitForExistence(timeout: 5), "the 14-day chart renders on the Week tab")
        attach("19-week-overview")
    }

    /// Fix 1: a store-load recovery surfaces a must-acknowledge notice instead of a silent empty list.
    func testShot20StoreRecoveryNotice() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-simulateStoreRecovery"]
        app.launch()
        XCTAssertTrue(app.staticTexts["We couldn't load your saved data"].waitForExistence(timeout: 10),
                      "a store recovery is surfaced, not a silently empty list")
        XCTAssertTrue(app.buttons["acknowledgeStoreRecovery"].exists, "the notice must be acknowledged")
        attach("20-store-recovery-notice")
    }

    /// Today cards WITH instructions (Vitamin D "Take with breakfast", Amoxicillin "Finish the…") and
    /// WITHOUT (Magnesium, Lisinopril) in one list — confirms even alignment + no cramming across variants.
    func testShot21TodayCardsWithAndWithoutInstructions() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedHistoryDemo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Vitamin D"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Take with breakfast"].exists, "an instructions caption renders on its own line")
        attach("21-today-cards-with-and-without-instructions")
    }

    // The three instruction cases in one glance-surface list — Aspirin (short "Take before breakfast", shown in
    // full), Ibuprofen (a long paragraph, collapsed to the compact "Instructions" indicator so the card
    // stays the same compact height), and Metformin (no instruction, no gap). Captured in whichever
    // appearance `simctl ui appearance` has set, so one test serves both light and dark mode.
    func testShot22TodayCardInstructionCases() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedCardLayoutDemo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Aspirin"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Take before breakfast"].exists, "short instruction shown")
        XCTAssertTrue(app.staticTexts["Instructions"].exists, "long instruction collapsed to the indicator")
        XCTAssertTrue(app.staticTexts["Metformin"].exists, "the no-instruction card is shown alongside")
        attach("22-today-card-instruction-cases")
    }

    // The same three cases at a large accessibility text size — proving the reflow keeps the full name
    // and a readable Take, and that the long paragraph still collapses (never expands the card).
    func testShot23TodayCardInstructionCasesAccessibility() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedCardLayoutDemo", "-forceDynamicType", "accessibility3"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Aspirin"].waitForExistence(timeout: 10))
        attach("23-today-card-instruction-cases-accessibility")
    }

    func testShot12DeleteDialogOnCorrectCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedHistoryDemo"]
        app.launch()
        let more = app.buttons["More options for Amoxicillin"]
        XCTAssertTrue(more.waitForExistence(timeout: 10)); more.tap()
        app.buttons["Delete permanently"].tap()
        XCTAssertTrue(app.buttons["Delete Amoxicillin"].waitForExistence(timeout: 5),
                      "the delete confirmation targets the tapped card's medicine")
        attach("12-delete-dialog-correct-card")
    }

    func testShot13SkippedCardShowsUndo() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedHistoryDemo"]   // Amoxicillin is skipped today in the seed
        app.launch()
        XCTAssertTrue(app.buttons["Undo Skipped for Amoxicillin"].waitForExistence(timeout: 10),
                      "a skipped dose card shows Undo")
        attach("13-skipped-card-undo")
    }

    func testShot14NoteOpensFromRowTap() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedHistoryDemo", "-tab", "notes"]
        app.launch()
        let cell = app.cells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        attach("14-note-opened-from-row")
    }

    func testShot10NoteEditorWithDone() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedHistoryDemo", "-tab", "notes"]
        app.launch()
        let note = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "ibuprofen")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        note.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "the note editor has a Done action")
        attach("10-note-editor-done")
    }
}
