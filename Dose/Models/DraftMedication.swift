import Foundation

/// AI/scan output, held in memory only — NOT a SwiftData `@Model`. This keeps "AI never touches
/// SwiftData" literally true and lets `name` be optional in a draft while a persisted `Medicine`
/// always has one. A draft becomes a `Medicine` only when the user confirms it in the review gate.
///
/// `id` is a client-only identifier (for SwiftUI lists) and is excluded from the wire format.
/// Decoding is lenient (defaults for absent fields) so a schema tweak server-side can't crash the
/// client; the edge function nonetheless emits every field via Structured Outputs.
struct DraftMedication: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String?
    var dosage: String?
    var form: String?
    var frequency: String?
    var schedule: [String]          // 24h "HH:mm" strings
    var quantity: String?
    var scheduleInferred: Bool
    var uncertainFields: [String]
    var confidence: Confidence
    var requiresReview: Bool

    enum CodingKeys: String, CodingKey {
        case name, dosage, form, frequency, schedule, quantity
        case scheduleInferred, uncertainFields, confidence, requiresReview
    }

    init(
        id: UUID = UUID(),
        name: String? = nil,
        dosage: String? = nil,
        form: String? = nil,
        frequency: String? = nil,
        schedule: [String] = [],
        quantity: String? = nil,
        scheduleInferred: Bool = false,
        uncertainFields: [String] = [],
        confidence: Confidence = .low,
        requiresReview: Bool = true
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.form = form
        self.frequency = frequency
        self.schedule = schedule
        self.quantity = quantity
        self.scheduleInferred = scheduleInferred
        self.uncertainFields = uncertainFields
        self.confidence = confidence
        self.requiresReview = requiresReview
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        dosage = try c.decodeIfPresent(String.self, forKey: .dosage)
        form = try c.decodeIfPresent(String.self, forKey: .form)
        frequency = try c.decodeIfPresent(String.self, forKey: .frequency)
        schedule = try c.decodeIfPresent([String].self, forKey: .schedule) ?? []
        quantity = try c.decodeIfPresent(String.self, forKey: .quantity)
        scheduleInferred = try c.decodeIfPresent(Bool.self, forKey: .scheduleInferred) ?? false
        uncertainFields = try c.decodeIfPresent([String].self, forKey: .uncertainFields) ?? []
        confidence = try c.decodeIfPresent(Confidence.self, forKey: .confidence) ?? .low
        requiresReview = try c.decodeIfPresent(Bool.self, forKey: .requiresReview) ?? true
    }
}

/// The exact response envelope returned by the `parse-medication` edge function: one input can
/// yield several medicines, so the review screen renders N cards.
struct ParseMedicationResponse: Codable {
    var medicines: [DraftMedication]
}
