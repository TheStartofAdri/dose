import Foundation

/// Whether a `Medicine` has been confirmed by a human and may drive Execution Mode.
/// Only `.confirmed` medicines reach the Today screen and notifications. A `.draft`
/// (produced by AI/scan) can never schedule reminders.
enum TrustState: String, Codable, Sendable {
    case draft
    case confirmed
}

/// A real action recorded against a scheduled slot. `.skipped` is an explicit, intentional
/// skip (e.g. the prescriber paused the med) and is treated as neutral for streaks — distinct
/// from a forgotten dose, which is a *computed* miss and never has a log at all.
enum DoseAction: String, Codable, Sendable {
    case taken
    case skipped
    case snoozed
}

/// Parser confidence for an AI/scan-produced draft. Drives how hard the review screen pushes back.
enum Confidence: String, Codable, Sendable {
    case high
    case medium
    case low
}

/// A tracked health metric's kind (v8) — a subjective **symptom** (0–10 severity) or an objective
/// **vital** (a numeric measurement with a unit). Consumer-facing categories, not clinical codes.
enum MetricKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case symptom
    case vital
    var id: String { rawValue }
}

/// How a metric's value is captured: a 0–10 severity scale (symptoms/mood/pain) or a free number with a
/// unit (weight, blood pressure, glucose…).
enum MetricValueKind: String, Codable, Sendable {
    case severity   // Int 0...10
    case number     // Double + unit
}

/// Where a `MetricEntry` came from — the user typed it, or it synced from HealthKit (Phase 3).
enum MetricSource: String, Codable, Sendable {
    case manual
    case healthKit
}
