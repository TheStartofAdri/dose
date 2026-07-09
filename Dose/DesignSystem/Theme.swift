import SwiftUI

/// Status colours and labels — the calm, Apple-Health-adjacent palette. Green = taken,
/// amber = due, red = missed, neutral = upcoming/skipped, blue = snoozed.
enum DoseTheme {
    static func color(for status: DoseStatus) -> Color {
        // Routes through the single `DoseColors` palette (redesign v1) — behaviour-preserving.
        switch status {
        case .upcoming: DoseColors.neutral
        case .due:      DoseColors.due
        case .missed:   DoseColors.missed
        case .taken:    DoseColors.taken
        case .skipped:  DoseColors.neutral
        case .snoozed:  DoseColors.snoozed
        }
    }

    static func label(for status: DoseStatus) -> String {
        switch status {
        case .upcoming: "Upcoming"
        case .due:      "Due now"
        case .missed:   "Missed"
        case .taken:    "Taken"
        case .skipped:  "Skipped"
        case .snoozed:  "Snoozed"
        }
    }

    static func icon(for status: DoseStatus) -> String {
        switch status {
        case .upcoming: "clock"
        case .due:      "bell.fill"
        case .missed:   "exclamationmark.circle.fill"
        case .taken:    "checkmark.circle.fill"
        case .skipped:  "minus.circle.fill"
        case .snoozed:  "moon.zzz.fill"
        }
    }

    /// Whether the dose is settled (no further action expected on Today).
    static func isSettled(_ status: DoseStatus) -> Bool {
        status == .taken || status == .skipped
    }
}
