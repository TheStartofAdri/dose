import Foundation
import Observation

/// Observable, app-wide notice that the AI backend host couldn't be reached at launch — so an unreachable
/// server (a paused/deleted project → DNS `-1003`, or the device offline → `-1009`) surfaces in Settings
/// up front, instead of only when the user taps Generate/Analyze and hits `ParserError.unreachable`.
///
/// Diagnostics only, and deliberately NON-BLOCKING: the probe runs in a detached startup Task and never
/// gates the core loop (tracking, reminders, history all work regardless of the result). Mirrors the
/// `NotificationStatus` / `StoreHealth` pattern — a shared `@Observable` whose flag a SwiftUI `body`
/// reads to show a banner.
@MainActor
@Observable
final class AIBackendHealth {
    static let shared = AIBackendHealth()

    /// True once a startup probe found the configured AI backend unreachable (DNS/offline). Read this in
    /// a `body` to gate the Settings notice; Observation re-renders when it flips.
    private(set) var isUnreachable = false

    /// Gate the banner on this so it (and its padding) takes no space when the backend is healthy.
    var hasNotice: Bool { isUnreachable }

    private init() {
        #if DEBUG
        // UITest / screenshot seam: force the unreachable banner without needing a real dead host.
        if CommandLine.arguments.contains("-stubAIBackendUnreachable") { isUnreachable = true }
        #endif
    }

    /// Non-blocking startup reachability ping. A cheap `OPTIONS` to the functions base: `URLSession` only
    /// throws on a TRANSPORT failure — a 401/404/405 HTTP *response* still means the host resolved and is
    /// reachable — so we flip `isUnreachable` ONLY on the `-1003`/`-1009` signal (via the same classifier
    /// the parser uses) and clear it otherwise. Never throws. Skipped when AI isn't configured (that's
    /// `notConfigured`, a different state — no false "server down" alarm before a backend even exists).
    func probe(using session: URLSession = .shared) async {
        guard AppConfig.aiConfigured, let base = AppConfig.parseMedicationEndpoint else { return }
        var request = URLRequest(url: base)
        request.httpMethod = "OPTIONS"
        request.timeoutInterval = 10
        do {
            _ = try await session.data(for: request)
            isUnreachable = false
        } catch {
            isUnreachable = ParserError.isUnreachableSignal(error)
        }
    }
}
