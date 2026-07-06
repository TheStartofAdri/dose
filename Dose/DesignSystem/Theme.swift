import SwiftUI

/// Status colours and labels — the calm, Apple-Health-adjacent palette. Green = taken,
/// amber = due, red = missed, neutral = upcoming/skipped, blue = snoozed.
enum DoseTheme {
    static func color(for status: DoseStatus) -> Color {
        switch status {
        case .upcoming: .secondary
        case .due:      .orange
        case .missed:   .red
        case .taken:    .green
        case .skipped:  .secondary
        case .snoozed:  .blue
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
