import Foundation

/// Shared `@AppStorage` keys so views and the scheduler agree on the same defaults.
enum SettingsKeys {
    static let escalationEnabled = "settings.escalationEnabled"
    static let aiEnabled = "settings.aiEnabled"
    static let soundEnabled = "settings.soundEnabled"
    static let appearance = "settings.appearance"     // "system" | "light" | "dark"
    /// One-time explicit consent before the FIRST AI parse sends text/photo off-device to Anthropic
    /// (Apple 5.1.2(i)). Default false → the consent prompt shows once, then never again.
    static let aiConsentGiven = "settings.aiConsentGiven"

    /// Reminder sound defaults to on; `UserDefaults.bool` returns false for an unset key, so read
    /// through this helper.
    static var soundEnabled_default: Bool {
        UserDefaults.standard.object(forKey: soundEnabled) as? Bool ?? true
    }
}
