import Foundation

/// Single source of truth for the app's published legal links. The paywall (App Review requires Terms +
/// Privacy links there) and the Settings "About" section both link to these exact URLs — defined once so
/// the two surfaces can never drift. `privacy` is the live policy at dose-med-tracker.com; `terms` is
/// Apple's standard EULA (Dose ships no separate Terms page).
enum LegalLinks {
    static let privacy = URL(string: "https://dose-med-tracker.com/privacy")!
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
