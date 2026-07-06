import Foundation

/// The features gated behind `Entitlements.isPremium`. Everything NOT in this set — Today, take/skip/undo,
/// manual add, reminders/notifications, history, notes — stays free for everyone, including a lapsed user
/// (cutting off a medication user's dose reminders is a safety problem). The enum labels the unlock paywall
/// and lets a unit test lock the gated set so a feature can't silently be added to or dropped from it.
enum PremiumFeature: String, CaseIterable, Identifiable {
    case reportExport
    case aiTextEntry
    case scanLabel
    case weeklyView

    var id: String { rawValue }

    /// Short name shown in the "Unlock …" paywall headline.
    var title: String {
        switch self {
        case .reportExport: "Adherence reports"
        case .aiTextEntry:  "Add by describing it"
        case .scanLabel:    "Scan a label"
        case .weeklyView:   "This week"
        }
    }
}
