import Foundation

/// Calls the `parse-medication` edge function. Sends the locked request contract and maps every
/// failure mode (refusal, max_tokens, HTTP, network, decode) to a typed `ParserError`.
struct RemoteMedicationParser: MedicationParser {
    struct ErrorBody: Decodable { let error: String }   // internal so the mapper is unit-testable

    /// How long to wait for the parse before giving up, so a hung backend doesn't spin the
    /// "Generate/Reading label…" state indefinitely (URLSession's default is 60s).
    static let requestTimeout: TimeInterval = 30

    /// Pure status→error mapping, extracted from `parse` so it's unit-testable without a live URLSession.
    /// Returns `nil` for a 200 (proceed to decode). Only the server's explicit `server_misconfigured`
    /// 500 is `.notConfigured`; any other 500 is a TRANSIENT `.server(500)` ("try again"), because the
    /// edge function can 500 on an uncaught upstream fault too — not just a missing key (AI1).
    static func error(forStatus status: Int, body: Data) -> ParserError? {
        switch status {
        case 200:
            return nil
        case 400:
            if let b = try? JSONDecoder().decode(ErrorBody.self, from: body), b.error == "too_long" {
                return .tooLong
            }
            return .server(400)
        case 422:
            if let b = try? JSONDecoder().decode(ErrorBody.self, from: body) {
                if b.error == "refusal" { return .refusal }
                if b.error == "incomplete" { return .incomplete }
            }
            return .server(422)
        case 500:
            if let b = try? JSONDecoder().decode(ErrorBody.self, from: body), b.error == "server_misconfigured" {
                return .notConfigured
            }
            return .server(500)
        default:
            return .server(status)
        }
    }

    func parse(_ input: ParserInput) async throws -> [DraftMedication] {
        guard let endpoint = AppConfig.parseMedicationEndpoint, let anonKey = AppConfig.supabaseAnonKey else {
            throw ParserError.notConfigured
        }

        var body: [String: Any] = ["timezone": TimeZone.current.identifier]
        switch input {
        case .text(let text):
            body["inputType"] = "text"
            body["inputText"] = text
            body["locale"] = Locale.current.identifier
        case .scan(let ocrText):
            body["inputType"] = "scan"
            body["ocrText"] = ocrText
            // Scanning is dual-language (EN+RU); the parser handles either, so just hint the device locale.
            body["locale"] = Locale.current.identifier
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // -1003 (host won't resolve) / -1009 (offline) become the distinct .unreachable; every other
            // transport failure keeps its detailed description via .network.
            throw ParserError.from(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ParserError.network("No HTTP response")
        }

        if let mapped = Self.error(forStatus: http.statusCode, body: data) {
            throw mapped
        }

        do {
            return try JSONDecoder().decode(ParseMedicationResponse.self, from: data).medicines
        } catch {
            throw ParserError.decoding
        }
    }
}
