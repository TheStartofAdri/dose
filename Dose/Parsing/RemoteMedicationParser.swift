import Foundation

/// Calls the `parse-medication` edge function. Sends the locked request contract and maps every
/// failure mode (refusal, max_tokens, HTTP, network, decode) to a typed `ParserError`.
struct RemoteMedicationParser: MedicationParser {
    private struct ErrorBody: Decodable { let error: String }

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

        switch http.statusCode {
        case 200:
            break
        case 422:
            if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                if body.error == "refusal" { throw ParserError.refusal }
                if body.error == "incomplete" { throw ParserError.incomplete }
            }
            throw ParserError.server(422)
        case 500:
            // The function returns 500 only when its Anthropic key isn't configured.
            throw ParserError.notConfigured
        default:
            throw ParserError.server(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(ParseMedicationResponse.self, from: data).medicines
        } catch {
            throw ParserError.decoding
        }
    }
}
