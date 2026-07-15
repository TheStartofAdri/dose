import Foundation

/// The result of creating a caregiver share — the token, the caregiver-facing view URL, and when it
/// auto-expires. Persisted locally (`CaregiverShareStore`) so the app can show status + revoke.
struct CaregiverShareResult: Codable, Equatable {
    let token: String
    let viewUrl: URL
    let expiresAt: Date
}

enum CaregiverShareError: Error, Equatable {
    case notConfigured
    case network(String)
    case server(Int)
    case decoding
}

/// A tiny transport seam so the client is unit-testable without a live server (the real one is
/// `URLSession`). Mirrors how the app keeps network calls testable elsewhere.
protocol CaregiverShareTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionShareTransport: CaregiverShareTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CaregiverShareError.network("No HTTP response") }
        return (data, http)
    }
}

/// Uploads a minimized, read-only `CaregiverShareSnapshot` to the `caregiver-share` edge function and
/// revokes it. The snapshot is built on-device (HealthKit-sourced values already excluded); this is the
/// point where it leaves the device, so the flow is premium-gated + consent-gated in the UI layer.
struct CaregiverShareClient {
    var transport: CaregiverShareTransport = URLSessionShareTransport()
    /// Defaults to the configured Supabase endpoint/key; overridable in tests to exercise the full
    /// request+parse path without the app's real (placeholder-in-dev) config.
    var endpoint: URL? = AppConfig.caregiverShareEndpoint
    var anonKey: String? = AppConfig.supabaseAnonKey
    static let requestTimeout: TimeInterval = 30

    struct ErrorBody: Decodable { let error: String }   // internal so the mapper is unit-testable

    /// Pure status→error mapping, extracted so it's unit-testable without a live transport (mirrors
    /// `RemoteMedicationParser.error(forStatus:body:)`). `nil` for a 200 → proceed. Only an explicit
    /// `server_misconfigured` 500 is `.notConfigured`; any OTHER 500 (a gateway/unhandled fault) is a
    /// TRANSIENT `.server(500)` — otherwise a blip would tell the user "sharing isn't set up yet."
    static func error(forStatus status: Int, body: Data = Data()) -> CaregiverShareError? {
        switch status {
        case 200:
            return nil
        case 500:
            if let b = try? JSONDecoder().decode(ErrorBody.self, from: body), b.error == "server_misconfigured" {
                return .notConfigured
            }
            return .server(500)
        default:
            return .server(status)
        }
    }

    func createShare(_ snapshot: CaregiverShareSnapshot, ttlDays: Int = 7) async throws -> CaregiverShareResult {
        guard let endpoint, let anonKey else {
            throw CaregiverShareError.notConfigured
        }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let body = try enc.encode(SharePost(snapshot: snapshot, ttlDays: ttlDays))

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = body

        let (data, http) = try await sendMapping(request)
        if let mapped = Self.error(forStatus: http.statusCode, body: data) { throw mapped }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = Self.flexibleISO8601
        guard let result = try? dec.decode(CaregiverShareResult.self, from: data) else {
            throw CaregiverShareError.decoding
        }
        return result
    }

    /// ISO-8601 decode tolerant of BOTH fractional and whole-second timestamps. The server's `expiresAt`
    /// is a JS `Date.toISOString()`, which ALWAYS carries milliseconds (e.g. "…:25.243Z"); Swift's
    /// built-in `.iso8601` strategy rejects fractional seconds, so a real 200 would otherwise fail to
    /// decode and break every create.
    static let flexibleISO8601: JSONDecoder.DateDecodingStrategy = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let d = withFraction.date(from: s) ?? plain.date(from: s) { return d }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Invalid ISO-8601 date: \(s)"))
        }
    }()

    func revoke(token: String) async throws {
        guard let endpoint, let anonKey else {
            throw CaregiverShareError.notConfigured
        }
        var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "t", value: token)]
        guard let url = comps?.url else { throw CaregiverShareError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        let (data, http) = try await sendMapping(request)
        if let mapped = Self.error(forStatus: http.statusCode, body: data) { throw mapped }
    }

    private func sendMapping(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do { return try await transport.send(request) }
        catch let e as CaregiverShareError { throw e }
        catch { throw CaregiverShareError.network(error.localizedDescription) }
    }

    private struct SharePost: Encodable {
        let snapshot: CaregiverShareSnapshot
        let ttlDays: Int
    }
}

/// Persists the ONE active caregiver share locally (there's at most one link at a time), so the app can
/// show "shared until …" and offer revoke. A plain Codable blob in UserDefaults — no schema migration
/// for a single, ephemeral, revocable token.
enum CaregiverShareStore {
    private static let key = "caregiver.share.active"

    static var current: CaregiverShareResult? {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            return try? dec.decode(CaregiverShareResult.self, from: data)
        }
        set {
            guard let newValue else { UserDefaults.standard.removeObject(forKey: key); return }
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            UserDefaults.standard.set(try? enc.encode(newValue), forKey: key)
        }
    }

    /// The active share, but only if it hasn't expired — an expired token is treated as no share.
    static func active(now: Date = .now) -> CaregiverShareResult? {
        guard let s = current, s.expiresAt > now else { return nil }
        return s
    }

    static func clear() { current = nil }
}
