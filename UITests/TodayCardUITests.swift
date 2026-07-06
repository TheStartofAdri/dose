import XCTest
import UIKit

/// Locks the Today-card behaviour that regressed on device:
///  - item 1: the medicine name stays readable next to a fixed, compact Take control,
///  - item 2: a Take can be undone (the slot reverts),
///  - item 6: tapping the card opens the medicine detail,
///  - the visible ⋯ menu archives (reusing the existing logic, history preserved).
final class TodayCardUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func addMedicine(_ app: XCUIApplication, name: String) {
        app.buttons["Add medicine"].firstMatch.tap()
        let manual = app.staticTexts["Manual entry"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5)); manual.tap()
        let field = app.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(name)
        app.buttons["manualSave"].tap()
        // Manual save offers the optional post-save extras step; skip it to return to Today.
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 5) { skip.tap() }
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }

    // Item 1 — the name is visible alongside a compact Take that doesn't overlap or crowd it out.
    func testCardNameReadableAlongsideCompactTake() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-uiTestReset"]
        app.launch()
        addMedicine(app, name: "Ibuprofen")

        let nameLabel = app.staticTexts["Ibuprofen"]
        let take = app.buttons["Take Ibuprofen"]
        XCTAssertTrue(nameLabel.exists && nameLabel.isHittable, "the name must be visible/hittable")
        XCTAssertTrue(take.exists && take.isHittable, "the Take control must be present")

        // The name occupies its own space to the left and is not covered by the Take control,
        // and the Take control is compact (the regression was a wide button truncating the name).
        XCTAssertLessThanOrEqual(nameLabel.frame.maxX, take.frame.minX + 1,
                                 "the name must not be overlapped by the Take control")
        XCTAssertLessThan(take.frame.width, 110, "the Take control must stay compact, not grow wide")
        XCTAssertGreaterThan(nameLabel.frame.width, take.frame.width,
                             "the name gets priority width over the Take control")
    }

    // Regression guard for the REAL card in the NAME-LEADING layout: the name leads beside the icon (where
    // the big time used to be) with the dose stacked directly under it; the small time sits at the top-right
    // with the Take/⋯ controls below it; the instruction caption and status chip are on full-width rows at
    // the card's far-left edge, sharing one leading edge with each other; a short instruction ("Take before
    // breakfast") shown in full; name readable. Queries are scoped to the Aspirin card because the seed has
    // three overdue cards (so "Missed" and the doseTime/instructionRow/statusChip identifiers repeat).
    func testRealCardShapeStacksCleanlyAndNameStaysReadable() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedCardLayoutDemo"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Aspirin"].waitForExistence(timeout: 10), "the card is visible")
        let card = app.cells.containing(.staticText, identifier: "Aspirin").firstMatch
        let name = card.staticTexts["Aspirin"]
        let dosage = card.staticTexts["2 pills"]
        let time = card.staticTexts["doseTime"]
        let instrRow = card.otherElements["instructionRow"]   // the instruction row container (its leading edge)
        let statusBox = card.otherElements["statusChip"]      // the status chip container (its leading edge)
        let instrText = card.staticTexts["Take before breakfast"]
        let take = card.buttons["Take Aspirin"]
        let more = card.buttons["More options for Aspirin"]

        XCTAssertTrue(dosage.exists, "the dosage line is visible")
        XCTAssertTrue(time.exists, "the time is visible")
        XCTAssertTrue(instrRow.exists, "the instruction row is present")
        XCTAssertTrue(statusBox.exists, "the status chip is present")
        XCTAssertTrue(take.exists && more.exists, "the Take + ⋯ controls are present")

        // Name fully rendered, never clipped to "Aspi" (~33pt); a full "Aspirin" is ~56pt.
        XCTAssertGreaterThan(name.frame.width, 45, "the medicine name renders in full, never 'Aspi'")
        XCTAssertEqual(name.label, "Aspirin", "the full name is present (not a truncated label)")

        // The NAME leads beside the icon — near the card's leading edge, where the big time used to be
        // (it was indented to ~145pt when the time led on the left).
        XCTAssertLessThan(name.frame.minX, 90,
                          "the name is the leading text, beside the icon (not indented behind the time)")
        // The DOSE is directly below the name, sharing its exact leading X.
        XCTAssertLessThanOrEqual(abs(dosage.frame.minX - name.frame.minX), 1,
                                 "the dose shares the name's exact leading edge")
        XCTAssertGreaterThan(dosage.frame.minY, name.frame.minY, "the dose is directly below the name")

        // The TIME is a small top-right timestamp: on the right half of the card, near the top (on the
        // name's line). With the old layout the time was the big number on the LEFT (~74pt).
        XCTAssertGreaterThan(time.frame.minX, card.frame.midX,
                             "the time sits in the top-right, not on the left")
        XCTAssertLessThanOrEqual(abs(time.frame.minY - name.frame.minY), 8,
                                 "the time is near the top, on the name's line")

        // The TAKE is below the time, on the right.
        XCTAssertGreaterThan(take.frame.minY, time.frame.minY, "Take sits below the time")
        XCTAssertGreaterThan(take.frame.minX, card.frame.midX, "Take is on the right side")
        XCTAssertLessThan(take.frame.width, 110, "the Take control stays compact")

        // Instruction + status: full-width rows at the card's far-left edge (left of the name), sharing
        // one leading edge with each other, stacked below the name/dose.
        XCTAssertLessThanOrEqual(abs(instrRow.frame.minX - statusBox.frame.minX), 1.5,
                                 "the instruction and status share one exact leading edge with each other")
        XCTAssertLessThan(instrRow.frame.minX, name.frame.minX,
                          "that shared edge is the card's far-left edge, left of the name")
        XCTAssertGreaterThan(instrRow.frame.minY, dosage.frame.minY, "the instruction is below the dose")
        XCTAssertGreaterThan(statusBox.frame.minY, instrRow.frame.minY, "the status chip is below the instruction")
        // The instruction sits TIGHT under the dose (grouped with the name/dose), not floating in a gap
        // below the taller time+Take right column.
        XCTAssertLessThanOrEqual(instrRow.frame.minY - dosage.frame.maxY, 12,
                                 "the instruction is tight under the dose, not floating below the Take")

        // The short instruction shows IN FULL on one line (not collapsed to the ~67pt "Instructions"
        // indicator); the full-width row gives it room.
        XCTAssertTrue(instrText.exists, "the short instruction shows in full, not collapsed")
        XCTAssertGreaterThan(instrText.frame.width, 110, "the instruction text is the full string, not the indicator")
    }

    // The harder guard: at a large ACCESSIBILITY text size — the condition that starved the text column
    // on device — the name must NOT hyphenate/clip across multiple lines and "Take" must NOT shrink to
    // "T…". The old fixed-26pt time + hard-clamped 56pt Take squeezed the name onto 2–3 lines (frame
    // height ~95pt) and clipped Take to its 56pt frame; the fix reflows so the name gets the full width
    // (one line) and Take grows to fit. Dynamic Type is forced in-app via `-forceDynamicType` so this is
    // deterministic regardless of the simulator's global setting.
    func testNameAndTakeSurviveLargeAccessibilityText() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedCardLayoutDemo", "-forceDynamicType", "accessibility3"]
        app.launch()

        let name = app.staticTexts["Aspirin"]
        let take = app.buttons["Take Aspirin"]
        let instructions = app.staticTexts["Take before breakfast"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the name is visible at a large accessibility size")
        XCTAssertEqual(name.label, "Aspirin", "the full name is present, not clipped")

        // The name renders on a single line (it gets the full width) — not squeezed onto 2–3 lines.
        // One line at this size is ~48pt tall; the starved old layout wrapped it to ~95pt.
        XCTAssertLessThan(name.frame.height, 70,
                          "the name must stay on one line (it must not hyphenate/wrap from being starved)")
        // "Take" is fully readable, not clipped to "T…": its width grows past the old fixed 56pt frame.
        XCTAssertGreaterThan(take.frame.width, 65, "Take must grow to fit its label, never clip to 'T…'")
        // The short instruction still shows in full (it fits one line even at the larger reflow width).
        XCTAssertTrue(instructions.exists, "the short instruction is still shown in full at a large text size")
    }

    // The instruction rule on the glance surface: a SHORT instruction shows in full on one line; a LONG
    // paragraph collapses to a compact "Instructions" indicator (the paragraph itself is NOT rendered on
    // the card, so it can't grow it); NO instruction shows neither. The long-collapsed card must be the
    // SAME height as the short-instruction card (the long text never expands the card), and all three
    // stay within a tight, compact bound. (Seed: Aspirin "Take before breakfast", Ibuprofen a long paragraph,
    // Metformin none.)
    func testShortInstructionShownLongCollapsesToIndicatorNoneAbsent() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedCardLayoutDemo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Aspirin"].waitForExistence(timeout: 10))

        // SHORT → shown in full.
        XCTAssertTrue(app.staticTexts["Take before breakfast"].exists, "a short instruction is shown in full on the card")

        // LONG → the compact indicator is shown, and the paragraph text is NOT rendered on Today at all.
        XCTAssertTrue(app.staticTexts["Instructions"].exists, "a long instruction collapses to the 'Instructions' indicator")
        let paragraphOnToday = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Take one tablet")).count
        XCTAssertEqual(paragraphOnToday, 0, "the long paragraph must NOT be rendered on the card (no paragraph eating the card)")

        // NONE → neither an instruction nor an indicator on that card.
        let metforminCell = app.cells.containing(.staticText, identifier: "Metformin").firstMatch
        XCTAssertFalse(metforminCell.staticTexts["Instructions"].exists,
                       "a card with no instruction shows no indicator (and no empty gap)")

        // The long-collapsed card must NOT be taller than the short-instruction card (both are exactly
        // one instruction line). And the no-instruction card is at most ~one line shorter — never a
        // paragraph's worth of extra height anywhere. So all three stay within a tight, compact bound.
        let hShort = app.cells.containing(.staticText, identifier: "Aspirin").firstMatch.frame.height
        let hLong = app.cells.containing(.staticText, identifier: "Ibuprofen").firstMatch.frame.height
        let hNone = app.cells.containing(.staticText, identifier: "Metformin").firstMatch.frame.height
        XCTAssertLessThanOrEqual(hLong, hShort + 2,
                                 "the long-instruction card must not grow beyond the one-line allowance (same height as the short card)")
        XCTAssertLessThanOrEqual(abs(hLong - hShort), 2, "short and long-collapsed cards are the same compact height")
        XCTAssertLessThan(hNone, hShort, "the no-instruction card is shorter (no instruction row)")
        XCTAssertLessThan(max(hShort, hLong) - hNone, 40,
                          "all three card heights stay within a consistent, compact bound (≤ one line apart)")
    }

    // Tapping the compact "Instructions" indicator reaches the medicine detail, which shows the FULL
    // instruction text (the part that's withheld from the glance card).
    func testLongInstructionIndicatorOpensDetailWithFullText() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedCardLayoutDemo"]
        app.launch()

        let indicator = app.staticTexts["Instructions"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 10), "the long instruction shows the indicator")
        indicator.tap()   // taps through to the card, which opens the medicine detail

        // The detail screen renders the WHOLE instruction (no line limit), so the paragraph is present.
        let fullText = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Take one tablet by mouth")).firstMatch
        XCTAssertTrue(fullText.waitForExistence(timeout: 5),
                      "the detail screen shows the full instruction text reached via the card's indicator")
        XCTAssertTrue(app.staticTexts["Schedule"].exists, "we are on the medicine detail screen")
    }

    // Guards the "you're late" cue: the top-right time renders in the OVERDUE/red colour for a `.missed`
    // and a `.due` dose, and in the NEUTRAL/gray colour for `.upcoming` and `.taken`. `timeColor` is
    // private and XCUITest can't read a view's colour, so this samples the actual rendered pixels of the
    // time element (its own screenshot) and measures "redness" = R − max(G,B): a red glyph (~255,59,48)
    // scores ~196, a gray glyph (~152,152,157) scores ~0. Without this, a regression that made `timeColor`
    // always gray would lose the overdue cue silently while every other test stayed green.
    func testOverdueTimeIsRedAndOtherwiseNeutral() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-seedTimeColorDemo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Overdue Med"].waitForExistence(timeout: 10), "the seeded cards are visible")

        func timeRedness(_ medName: String) -> CGFloat {
            let card = app.cells.containing(.staticText, identifier: medName).firstMatch
            let time = card.staticTexts["doseTime"]
            XCTAssertTrue(time.waitForExistence(timeout: 5), "\(medName) has a visible time")
            return Self.maxRedness(time.screenshot().image)
        }

        // Overdue (.missed) and due (.due) → RED. (timeColor reds both; either being made gray fails here.)
        XCTAssertGreaterThan(timeRedness("Overdue Med"), 60,
                             "an overdue (missed) dose must show a RED time — the 'you're late' cue")
        XCTAssertGreaterThan(timeRedness("Due Med"), 60,
                             "a due dose must show a RED time")
        // Not overdue → NEUTRAL gray (the `else` branch of timeColor).
        XCTAssertLessThan(timeRedness("Upcoming Med"), 40,
                          "an upcoming dose must show a neutral gray time, not red")
        XCTAssertLessThan(timeRedness("Taken Med"), 40,
                          "a taken dose must show a neutral gray time, not red")
    }

    /// Max "redness" (R − max(G,B)) over an image's pixels — high for red text, ~0 for gray/neutral text.
    private static func maxRedness(_ image: UIImage) -> CGFloat {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return 0 }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var maxRed: CGFloat = 0
        var i = 0
        while i < pixels.count {
            let redness = CGFloat(pixels[i]) - max(CGFloat(pixels[i + 1]), CGFloat(pixels[i + 2]))
            if redness > maxRed { maxRed = redness }
            i += 4
        }
        return maxRed
    }

    // Item 3 — a Skip is undoable (second tap), exactly like Take.
    func testSkipThenUndoReverts() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-uiTestReset"]
        app.launch()
        addMedicine(app, name: "Ibuprofen")

        // Swipe-left reveals "Skip today".
        app.staticTexts["Ibuprofen"].swipeLeft()
        app.buttons["Skip today"].tap()

        // The card settles to skipped and offers Undo.
        let undo = app.buttons["Undo Skipped for Ibuprofen"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "a skipped dose shows Undo")
        undo.tap()

        // Undo removes the skip → the dose is back to actionable (Take returns).
        XCTAssertTrue(app.buttons["Take Ibuprofen"].waitForExistence(timeout: 5),
                      "undo reverts the skip so Take returns")
        XCTAssertFalse(app.buttons["Undo Skipped for Ibuprofen"].exists)
    }

    // Deleting from the DETAIL screen must survive the pop: dismiss() only STARTS the animation while
    // the delete's save re-renders the view with an invalidated @Model (SwiftData fatal-error class).
    // Locks the previously-uncovered delete-from-detail flow end to end.
    func testDeleteFromDetailReturnsToTodaySafely() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-uiTestReset"]
        app.launch()
        addMedicine(app, name: "Ibuprofen")

        app.staticTexts["Ibuprofen"].tap()                        // card tap → detail (item 6 wiring)
        let manage = app.buttons["Manage medicine"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5), "the detail screen opened")
        manage.tap()
        app.buttons["Delete permanently"].tap()
        let confirm = app.buttons["Delete Ibuprofen"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the delete confirmation appeared")
        confirm.tap()

        // Back on Today (the add button is reachable again), the medicine is gone, the app is alive.
        XCTAssertTrue(app.buttons["Add medicine"].firstMatch.waitForExistence(timeout: 5),
                      "the pop landed back on Today without crashing")
        XCTAssertFalse(app.staticTexts["Ibuprofen"].exists, "the deleted medicine left Today")
        XCTAssertEqual(app.state, .runningForeground)
    }

    // Item 2 — undo an accidental Take.
    func testUndoRevertsATake() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-uiTestReset"]
        app.launch()
        addMedicine(app, name: "Ibuprofen")

        app.buttons["Take Ibuprofen"].tap()
        let undo = app.buttons["Undo Taken for Ibuprofen"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "a taken dose shows an Undo control")
        undo.tap()

        // The slot reverts: the Take control comes back, the Undo control is gone.
        XCTAssertTrue(app.buttons["Take Ibuprofen"].waitForExistence(timeout: 5),
                      "undo reverts the slot so Take returns")
        XCTAssertFalse(app.buttons["Undo Taken for Ibuprofen"].exists)
    }

    // Item 6 — tapping the card opens the medicine detail.
    func testTapCardOpensMedicineDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-uiTestReset"]
        app.launch()
        addMedicine(app, name: "Ibuprofen")

        app.staticTexts["Ibuprofen"].tap()   // tap the card body (not the Take/⋯ controls)
        XCTAssertTrue(app.staticTexts["Schedule"].waitForExistence(timeout: 5),
                      "the medicine detail screen (with a Schedule section) should open")
        XCTAssertTrue(app.staticTexts["Adherence"].exists, "detail shows this medicine's own history")
    }

    // The visible ⋯ menu archives from Today.
    func testEllipsisMenuArchivesFromToday() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipAuth", "-uiTestReset"]
        app.launch()
        addMedicine(app, name: "Test Med")

        let more = app.buttons["More options for Test Med"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "the ⋯ menu button should be visible on the card")
        more.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Archive"].exists)
        XCTAssertTrue(app.buttons["Delete permanently"].exists)

        app.buttons["Archive"].tap()
        let confirm = app.buttons["Archive Test Med"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["No medicines yet"].waitForExistence(timeout: 5),
                      "archived medicine leaves Today")
    }
}
