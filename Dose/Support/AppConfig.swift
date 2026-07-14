import Foundation

/// Reads Supabase configuration injected at build time (Secrets.xcconfig → Info.plist).
/// The anon key is public-safe; the Anthropic key never reaches the client.
enum AppConfig {
    static var supabaseURL: URL? {
        guard let value = infoString("SupabaseURL"),
              !value.contains("YOUR-PROJECT"),
              let url = URL(string: value)
        else { return nil }
        return url
    }

    static var supabaseAnonKey: String? {
        guard let value = infoString("SupabaseAnonKey"),
              !value.hasPrefix("YOUR_")
        else { return nil }
        return value
    }

    static var parseMedicationEndpoint: URL? {
        supabaseURL?.appending(path: "functions/v1/parse-medication")
    }

    /// The caregiver-share edge function (create / revoke / read-only web view). Same Supabase project
    /// as the parser; only present when the backend is configured.
    static var caregiverShareEndpoint: URL? {
        supabaseURL?.appending(path: "functions/v1/caregiver-share")
    }

    /// True only when real Supabase values have been provided. AI/scan features check this
    /// before calling the network and surface a friendly "set up the backend" message otherwise.
    static var aiConfigured: Bool {
        supabaseURL != nil && supabaseAnonKey != nil
    }

    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return value
    }
}
