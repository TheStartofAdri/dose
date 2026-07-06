import Foundation

/// Input to the parser. `inputType` distinguishes free text from OCR'd packaging text so the
/// backend can frame them differently.
enum ParserInput: Equatable {
    case text(String)
    case scan(ocrText: String)
}

/// Abstraction over the AI parser so the AI-text, scan, and note-analyze flows share the exact same
/// draft → review path. The production implementation is `RemoteMedicationParser`.
protocol MedicationParser {
    func parse(_ input: ParserInput) async throws -> [DraftMedication]
}

/// Builds the medicine name draft input from a note. Pure + testable: only the note's own text is
/// ever sent (always as `.text`, never scan) — the privacy guarantee that nothing else leaves the
/// device when the user explicitly analyzes a note.
enum NoteAnalysis {
    static func parserInput(for text: String) -> ParserInput { .text(text) }
}

/// Selects the parser implementation. Production → `RemoteMedicationParser`; a DEBUG `-stubParser`
/// launch flag swaps in a deterministic stub so UI tests / screenshots can drive the
/// analyze → review → confirm path without a network/backend.
enum MedicationParserFactory {
    static func make() -> MedicationParser {
        #if DEBUG
        if CommandLine.arguments.contains("-stubLowConfidence") { return StubMedicationParser(lowConfidence: true) }
        if CommandLine.arguments.contains("-stubParser") { return StubMedicationParser() }
        #endif
        return RemoteMedicationParser()
    }
}

#if DEBUG
/// Deterministic, no-network parser for tests/screenshots. Returns one draft so it must pass through
/// the review gate, and records the last input it received. `lowConfidence` returns a low-confidence
/// draft with uncertain name/dosage/form so the Review screen's field warnings render deterministically.
final class StubMedicationParser: MedicationParser {
    let lowConfidence: Bool
    private(set) var lastInput: ParserInput?

    init(lowConfidence: Bool = false) { self.lowConfidence = lowConfidence }

    func parse(_ input: ParserInput) async throws -> [DraftMedication] {
        lastInput = input
        return [DraftMedication(
            name: "Ibuprofen", dosage: "200 mg", form: "tablet", frequency: "twice a day",
            schedule: ["08:00", "20:00"], quantity: nil, scheduleInferred: true,
            uncertainFields: lowConfidence ? ["name", "dosage", "form"] : ["schedule"],
            confidence: lowConfidence ? .low : .medium, requiresReview: true
        )]
    }
}
#endif
