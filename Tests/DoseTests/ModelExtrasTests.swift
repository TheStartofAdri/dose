import XCTest
import SwiftData
@testable import Dose

/// Round-trips for the new optional Medicine attributes (item 1/2/3) and Note CRUD (item 5).
final class ModelExtrasTests: XCTestCase {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Medicine.self, DoseTime.self, DoseLog.self, Note.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @MainActor
    func testMedicineExtrasRoundTrip() throws {
        let ctx = try makeContext()
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        ctx.insert(Medicine(name: "Amoxicillin", dosage: "500 mg", trustState: .confirmed,
                            iconName: "capsule.fill", colorHex: "#FF375F", endDate: end, instructions: "with food"))
        try ctx.save()

        let med = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Medicine>()).first)
        XCTAssertEqual(med.iconName, "capsule.fill")
        XCTAssertEqual(med.colorHex, "#FF375F")
        XCTAssertEqual(med.endDate, end)
        XCTAssertEqual(med.instructions, "with food")
    }

    @MainActor
    func testMedicineExtrasDefaultNilWithSensibleFallback() throws {
        let ctx = try makeContext()
        ctx.insert(Medicine(name: "Plain", trustState: .confirmed))
        try ctx.save()

        let med = try XCTUnwrap(try ctx.fetch(FetchDescriptor<Medicine>()).first)
        XCTAssertNil(med.iconName)
        XCTAssertNil(med.colorHex)
        XCTAssertNil(med.endDate)
        XCTAssertNil(med.instructions)
        // A medicine with no chosen icon falls back to a sensible default.
        XCTAssertEqual(MedAppearance.icon(med.iconName), "pills.fill")
    }

    @MainActor
    func testNoteCreateEditDelete() throws {
        let ctx = try makeContext()
        let note = Note(text: "hello")
        ctx.insert(note); try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Note>()).count, 1)

        note.text = "edited"; try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Note>()).first?.text, "edited")

        ctx.delete(note); try ctx.save()
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Note>()).count, 0)
    }
}
