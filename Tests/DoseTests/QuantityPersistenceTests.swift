import XCTest
import SwiftData
@testable import Dose

/// BUG 1: quantity/pack-size must load into the Edit form, persist on save, and survive a store
/// round-trip. Before the fix, `Medicine` had no `quantity` property, `EditableDraft.init(editing:)`
/// omitted it, and `apply(to:)` never wrote it — so a typed quantity vanished on every save (new + edit).
final class QuantityPersistenceTests: XCTestCase {

    private func draft(quantity: String) -> EditableDraft {
        EditableDraft(name: "Amoxicillin", dosage: "500 mg", form: "capsule", quantity: quantity,
                      times: [.now], source: .manual)
    }

    /// `apply(to:)` writes a non-empty quantity onto the medicine. (Fail-before: never written → nil.)
    func testApplyWritesQuantity() {
        let med = Medicine(name: "placeholder")
        draft(quantity: "100 ml").apply(to: med, newDoseTimes: [])
        XCTAssertEqual(med.quantity, "100 ml")
    }

    /// A blank quantity normalizes to nil (no empty-string rows), matching dosage/form/instructions.
    func testEmptyQuantityPersistsAsNil() {
        let med = Medicine(name: "placeholder")
        draft(quantity: "   ").apply(to: med, newDoseTimes: [])
        XCTAssertNil(med.quantity, "a blank quantity is stored as nil, not an empty string")
    }

    /// Opening Edit on a medicine WITH a saved quantity loads it into the field (not the placeholder).
    /// (Fail-before: `init(editing:)` omitted quantity → "".)
    func testEditingLoadsSavedQuantity() {
        let med = Medicine(name: "Amoxicillin", quantity: "30 tablets")
        XCTAssertEqual(EditableDraft(editing: med).quantity, "30 tablets")
    }

    /// Open Edit and save WITHOUT touching quantity → the saved value is preserved (the data-loss case).
    func testEditWithoutTouchingQuantityPreservesIt() {
        let med = Medicine(name: "Amoxicillin", quantity: "100 ml")
        let edit = EditableDraft(editing: med)        // loads "100 ml"
        edit.apply(to: med, newDoseTimes: [])         // save, unchanged
        XCTAssertEqual(med.quantity, "100 ml", "editing without touching quantity must not wipe it")
    }

    /// Persistence round-trip through SwiftData (v5 store): save a medicine with a quantity, fetch it
    /// back, and confirm the Edit form would reload it — proves it's stored, not just set on the object.
    func testQuantitySurvivesStoreRoundTrip() throws {
        let container = try ModelContainer(
            for: DoseStore.currentSchema,
            configurations: [ModelConfiguration(schema: DoseStore.currentSchema, isStoredInMemoryOnly: true)])
        let ctx = ModelContext(container)

        let med = Medicine(name: "Amoxicillin", trustState: .confirmed)
        draft(quantity: "20 mg/ml").apply(to: med, newDoseTimes: [])
        ctx.insert(med)
        try ctx.save()

        let fetched = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Medicine>()).first)
        XCTAssertEqual(fetched.quantity, "20 mg/ml", "quantity persisted to the store")
        XCTAssertEqual(EditableDraft(editing: fetched).quantity, "20 mg/ml", "Edit reloads the stored quantity")
    }
}
