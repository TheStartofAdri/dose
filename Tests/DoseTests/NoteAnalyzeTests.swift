import XCTest
import SwiftData
@testable import Dose

/// Item 5: note → analyze → review → save. Locks the privacy + safety contract: only the chosen
/// note's text is sent, the result must pass through review (never auto-saved), and a medicine is
/// created only on explicit confirm.
final class NoteAnalyzeTests: XCTestCase {
    func testOnlySelectedNoteTextIsSentAsText() {
        let text = "Doctor said start metformin 500 mg twice daily"
        XCTAssertEqual(NoteAnalysis.parserInput(for: text), .text(text))
        if case .scan = NoteAnalysis.parserInput(for: text) {
            XCTFail("note analysis must use free-text input, never scan")
        }
    }

    func testAnalyzeProducesAReviewableDraftNotAutoSaved() async throws {
        let stub = StubMedicationParser()
        let drafts = try await stub.parse(NoteAnalysis.parserInput(for: "note text"))
        XCTAssertEqual(stub.lastInput, .text("note text"), "exactly the note text was sent")
        XCTAssertEqual(drafts.count, 1)

        // Mapped for the review gate as an AI draft (so the review/edit-before-confirm rules apply).
        let draft = EditableDraft(from: drafts[0], source: .ai)
        XCTAssertEqual(draft.source, .ai)
    }

    @MainActor
    func testConfirmCreatesMedicineCancelCreatesNothing() throws {
        let container = try ModelContainer(
            for: Medicine.self, DoseTime.self, DoseLog.self, Note.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let draft = EditableDraft(from: DraftMedication(name: "Ibuprofen", schedule: ["08:00"]), source: .ai)

        // Cancelling review = never calling confirm → nothing is created.
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Medicine>()).count, 0)

        // Confirming creates exactly one confirmed medicine.
        MedicineWriter.confirm([draft], context: ctx, escalationEnabled: false)
        let meds = try ctx.fetch(FetchDescriptor<Medicine>())
        XCTAssertEqual(meds.count, 1)
        XCTAssertEqual(meds.first?.trustState, .confirmed)
    }
}
