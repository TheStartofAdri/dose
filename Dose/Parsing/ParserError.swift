import Foundation

/// Typed parser failures, each mapped to a clean user-facing message. The UI always offers manual
/// entry as the fallback, so no failure is a dead end.
enum ParserError: LocalizedError {
    case notConfigured       // backend not set up, or server missing its key
    case refusal             // stop_reason == "refusal"
    case incomplete          // stop_reason == "max_tokens"
    case server(Int)
    case unreachable         // transport-level: host won't resolve (-1003) or device offline (-1009)
    case network(String)     // any other transport failure (timeout, TLS, connection reset, …)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "AI features aren't set up yet. You can still add this medicine manually."
        case .refusal:
            "Couldn't read that automatically. Please add the medicine manually."
        case .incomplete:
            "That was a bit too much to process. Try shorter input, or add it manually."
        case .server(let code):
            "The parser had a problem (code \(code)). Please try again or add it manually."
        case .unreachable:
            "Our AI server couldn't be reached — it may be temporarily down. You can still add this medicine manually."
        case .network(let detail):
            "Network problem: \(detail). Check your connection or add it manually."
        case .decoding:
            "Couldn't understand the parser's response. Please add the medicine manually."
        }
    }

    /// Maps a thrown transport error to a typed case. A host that won't resolve (`-1003 cannotFindHost`)
    /// or an offline device (`-1009 notConnectedToInternet`) is a distinct, actionable "backend
    /// unreachable" state — surfaced separately from the generic network message (and mirrored by the
    /// startup reachability probe). Every other failure keeps its detailed `localizedDescription`.
    static func from(_ error: Error) -> ParserError {
        isUnreachableSignal(error) ? .unreachable : .network(error.localizedDescription)
    }

    /// The single classification that BOTH the parser's `catch` and `AIBackendHealth`'s startup probe
    /// use, so "unreachable" means exactly the same thing in the error message and the launch banner:
    /// DNS-can't-find-host (`-1003`) or no-internet (`-1009`). Any other `URLError` (timeout, TLS, reset)
    /// is a normal network problem, not an "AI server is down" signal.
    static func isUnreachableSignal(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .cannotFindHost, .notConnectedToInternet: return true
        default: return false
        }
    }
}
