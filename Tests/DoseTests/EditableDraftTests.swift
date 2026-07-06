import XCTest
import SwiftData
@testable import Dose

/// Item 7: a fresh manual entry must start genuinely empty — no default/stray value (the "At" bug).
/// The data model carries no name default; the stray glyph came from iOS autofill on the field,
/// fixed by disabling content-type autofill in `LabeledDraftField`. This locks the model side.
final class EditableDraftTests: XCTestCase {
    func testFreshManualDraftHasEmptyName() {
        let draft = EditableDraft.empty()
        XCTAssertEqual(draft.name, "", "a new manual draft has no default name")
        XCTAssertTrue(draft.trimmedName.isEmpty)
        XCTAssertTrue(draft.blocksConfirm, "an empty name must block confirm/save")
    }

    func testFreshManualDraftHasEmptyOptionalFields() {
        let draft = EditableDraft.empty()
        XCTAssertEqual(draft.dosage, "")
        XCTAssertEqual(draft.form, "")
        XCTAssertEqual(draft.quantity, "")
        XCTAssertEqual(draft.source, .manual)
    }

    // MARK: - Item 2: low-confidence flag WARNS, it must not BLOCK a correct value

    /// A non-manual draft the parser flagged as low-confidence on name + dosage, with values that are
    /// actually correct. Confirm should be blockable *until the user acts*, then confirmable as-is.
    private func lowConfidenceDraft(name: String = "Aspirin", dosage: String = "100 mg") -> EditableDraft {
        EditableDraft(name: name, dosage: dosage, times: [.now],
                      source: .ai, uncertainFields: ["name", "dosage"], confidence: .low)
    }

    /// The crucial assertion: a freshly-built low-confidence draft blocks confirm and is NOT
    /// pre-acknowledged. "Reviewed" must be a deliberate user tap, never an on-render default.
    func testLowConfidenceFlagsBlockOnRenderAndAreNotPreAcknowledged() {
        let draft = lowConfidenceDraft()
        XCTAssertFalse(draft.trimmedName.isEmpty, "name is non-empty — only the flags can be blocking")
        XCTAssertTrue(draft.mustReview("name"))
        XCTAssertTrue(draft.mustReview("dosage"))
        XCTAssertFalse(draft.wasAcknowledged("name"), "Reviewed must NOT be set on render")
        XCTAssertFalse(draft.wasAcknowledged("dosage"), "Reviewed must NOT be set on render")
        XCTAssertTrue(draft.blocksConfirm, "a flagged-but-untouched draft blocks confirm")
    }

    /// "Looks right" (acknowledge) clears the block WITHOUT editing the value, and marks it Reviewed.
    func testAcknowledgeUnblocksWithoutChangingTheValue() {
        let draft = lowConfidenceDraft()
        let originalName = draft.name, originalDosage = draft.dosage

        draft.acknowledge("name")
        XCTAssertTrue(draft.blocksConfirm, "still blocked while the dosage flag remains")

        draft.acknowledge("dosage")
        XCTAssertFalse(draft.blocksConfirm, "acknowledging every flag unblocks confirm")
        XCTAssertFalse(draft.mustReview("name"))
        XCTAssertFalse(draft.mustReview("dosage"))
        XCTAssertTrue(draft.wasAcknowledged("name"))
        XCTAssertTrue(draft.wasAcknowledged("dosage"))
        // The human confirms the value AS-IS — acknowledgement never alters it.
        XCTAssertEqual(draft.name, originalName)
        XCTAssertEqual(draft.dosage, originalDosage)
    }

    /// Editing a flagged field still clears its block — but editing is not "Reviewed" (no green mark).
    func testEditingClearsFlagButDoesNotMarkReviewed() {
        let draft = lowConfidenceDraft()
        draft.markEdited("name")
        draft.markEdited("dosage")
        XCTAssertFalse(draft.blocksConfirm, "editing the flagged fields clears the block")
        XCTAssertFalse(draft.wasAcknowledged("name"), "edited is not the same as acknowledged")
        XCTAssertFalse(draft.wasAcknowledged("dosage"))
    }

    /// If the user acknowledges then goes back and edits, the Reviewed mark is dropped (it reflects
    /// the value they vouched for, which they've now changed).
    func testAcknowledgeThenEditDropsReviewedMark() {
        let draft = lowConfidenceDraft()
        draft.acknowledge("name")
        XCTAssertTrue(draft.wasAcknowledged("name"))
        draft.markEdited("name")
        XCTAssertFalse(draft.wasAcknowledged("name"), "editing clears the Reviewed mark")
    }

    /// An empty name is enforced independently of the acknowledgeable flags — it must still block
    /// even after every parser flag is acknowledged.
    func testEmptyNameStillBlocksAfterAcknowledgingFlags() {
        let draft = EditableDraft(name: "", dosage: "100 mg", times: [.now],
                                  source: .ai, uncertainFields: ["dosage"], confidence: .low)
        draft.acknowledge("dosage")
        XCTAssertTrue(draft.blocksConfirm, "an empty name blocks confirm regardless of acknowledgements")
    }

    /// A high-confidence (or non-flagged) AI draft carries no must-review flags and confirms freely.
    func testHighConfidenceAIDraftHasNoFlags() {
        let draft = EditableDraft(name: "Aspirin", dosage: "100 mg", times: [.now],
                                  source: .ai, uncertainFields: [], confidence: .high)
        XCTAssertFalse(draft.mustReview("name"))
        XCTAssertFalse(draft.blocksConfirm)
    }

    // MARK: - Fix 2: inferred / low-confidence schedule must be acknowledged (wrong cadence = harm)

    /// An inferred schedule is flagged regardless of overall confidence — medium here, so name/dosage
    /// are NOT flagged and the schedule is the only blocker (clean isolation).
    private func inferredScheduleDraft() -> EditableDraft {
        EditableDraft(name: "Ibuprofen", dosage: "200 mg", times: [.now],
                      source: .ai, uncertainFields: ["schedule"], scheduleInferred: true, confidence: .medium)
    }

    func testInferredScheduleBlocksOnRenderAndIsNotPreAcknowledged() {
        let draft = inferredScheduleDraft()
        XCTAssertFalse(draft.trimmedName.isEmpty)
        XCTAssertFalse(draft.mustReview("name"), "name is confident here — only the schedule is flagged")
        XCTAssertTrue(draft.mustReview("schedule"))
        XCTAssertFalse(draft.wasAcknowledged("schedule"), "Reviewed must NOT be set on render")
        XCTAssertTrue(draft.blocksConfirm, "an inferred cadence blocks confirm until reviewed")
    }

    func testAcknowledgingScheduleUnblocksWithoutChangingTimes() {
        let draft = inferredScheduleDraft()
        let originalTimes = draft.times
        draft.acknowledge("schedule")
        XCTAssertFalse(draft.blocksConfirm, "acknowledging the schedule unblocks confirm")
        XCTAssertFalse(draft.mustReview("schedule"))
        XCTAssertTrue(draft.wasAcknowledged("schedule"))
        XCTAssertEqual(draft.times, originalTimes, "acknowledgement never changes the times")
    }

    func testEditingScheduleClearsFlagButNotMarkedReviewed() {
        let draft = inferredScheduleDraft()
        draft.markEdited("schedule")
        XCTAssertFalse(draft.blocksConfirm, "editing the schedule clears the block")
        XCTAssertFalse(draft.wasAcknowledged("schedule"), "editing is not the same as acknowledged")
    }

    func testLowConfidenceScheduleInUncertainFieldsIsFlagged() {
        let draft = EditableDraft(name: "Ibuprofen", dosage: "200 mg", times: [.now],
                                  source: .ai, uncertainFields: ["schedule"], scheduleInferred: false, confidence: .low)
        XCTAssertTrue(draft.mustReview("schedule"))
        XCTAssertTrue(draft.blocksConfirm)
    }

    func testConfidentScheduleHasNoFlag() {
        let draft = EditableDraft(name: "Ibuprofen", dosage: "200 mg", times: [.now],
                                  source: .ai, uncertainFields: [], scheduleInferred: false, confidence: .high)
        XCTAssertFalse(draft.mustReview("schedule"))
        XCTAssertFalse(draft.blocksConfirm)
    }

    func testManualDraftScheduleNeverFlagged() {
        let draft = EditableDraft(name: "Aspirin", dosage: "100 mg", times: [.now], source: .manual)
        XCTAssertFalse(draft.mustReview("schedule"), "a manual schedule is the user's own — never flagged")
        XCTAssertFalse(draft.blocksConfirm)
    }

    // MARK: - Every-N-days anchor must survive an edit (wrong-day dosing bug)

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// THE bug: `init(editing:)` dropped the rule's `anchorDate` and `doseTimes()` re-anchored at the
    /// edit day, so editing ONLY the name of an "every 3 days" med (anchored Jun 15 → doses 15/18/21)
    /// on Jun 17 silently shifted the cycle to 17/20/23 — a wrong-day dosing error. The anchor must
    /// round-trip through the edit draft untouched.
    @MainActor
    func testEditingPreservesEveryNDaysAnchor() throws {
        let cal = utc
        let schema = DoseStore.currentSchema
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let ctx = ModelContext(container)
        let anchor = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let med = Medicine(name: "Metformin", trustState: .confirmed)
        let dt = DoseTime(hour: 8, minute: 0, intervalDays: 3, anchorDate: anchor)
        med.doseTimes = [dt]
        ctx.insert(med); ctx.insert(dt)

        let draft = EditableDraft(editing: med, calendar: cal)
        let editNow = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 14))!
        let rebuilt = draft.doseTimes(now: editNow, calendar: cal)

        XCTAssertEqual(rebuilt.count, 1)
        XCTAssertEqual(rebuilt.first?.intervalDays, 3, "the interval itself round-trips")
        XCTAssertEqual(rebuilt.first?.anchorDate, anchor,
                       "editing must not re-anchor the every-N-days cycle to the edit day")
    }

    /// Regression guard for the untouched path: a BRAND-NEW every-N-days draft (no prior rule) still
    /// anchors at the creation day — preserving the anchor is edit-only behavior.
    func testNewEveryNDaysDraftAnchorsAtCreationDay() {
        let cal = utc
        let draft = EditableDraft.empty(calendar: cal)
        draft.repeatMode = .everyNDays
        draft.intervalDays = 2
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 17, hour: 14))!
        let rebuilt = draft.doseTimes(now: now, calendar: cal)
        XCTAssertEqual(rebuilt.first?.anchorDate, cal.startOfDay(for: now),
                       "a new every-N-days schedule anchors at the day it was created")
    }
}
