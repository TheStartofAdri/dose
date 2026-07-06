import XCTest
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
}
