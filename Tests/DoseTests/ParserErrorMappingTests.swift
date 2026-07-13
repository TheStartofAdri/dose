import XCTest
@testable import Dose

/// The transport-error classification that turned a real device `-1003` (the paused-Supabase-project DNS
/// failure) into the generic "Network problem" message. Now `-1003 cannotFindHost` and `-1009 offline`
/// map to a distinct `.unreachable` case, and everything else keeps the detailed network message. This
/// same predicate (`isUnreachableSignal`) drives the startup reachability banner, so pinning it here
/// guards both surfaces at once.
final class ParserErrorMappingTests: XCTestCase {

    func testCannotFindHostMapsToUnreachable() {
        // -1003: the exact code the physical iPhone reported when the Supabase host stopped resolving.
        let mapped = ParserError.from(URLError(.cannotFindHost))
        guard case .unreachable = mapped else {
            return XCTFail("URLError -1003 must map to .unreachable, got \(mapped)")
        }
        XCTAssertEqual(mapped.errorDescription,
                       "Our AI server couldn't be reached — it may be temporarily down. You can still add this medicine manually.")
    }

    func testNotConnectedToInternetMapsToUnreachable() {
        // -1009: device offline — same user-facing "couldn't be reached" bucket.
        guard case .unreachable = ParserError.from(URLError(.notConnectedToInternet)) else {
            return XCTFail("URLError -1009 must map to .unreachable")
        }
    }

    func testGenericNetworkErrorStaysNetwork() {
        // A timeout is a real network problem but NOT "the server is down" — keep the detailed message.
        let mapped = ParserError.from(URLError(.timedOut))
        guard case .network(let detail) = mapped else {
            return XCTFail("a non-DNS/offline URLError must stay .network, got \(mapped)")
        }
        XCTAssertFalse(detail.isEmpty, "the underlying description is preserved for .network")
        XCTAssertNotEqual(mapped.errorDescription,
                          ParserError.unreachable.errorDescription,
                          ".network and .unreachable must read differently")
    }

    func testNonURLErrorStaysNetwork() {
        struct Weird: Error {}
        guard case .network = ParserError.from(Weird()) else {
            return XCTFail("a non-URLError must fall through to .network, never .unreachable")
        }
    }

    func testUnreachableSignalPredicateMatchesExactlyDNSAndOffline() {
        XCTAssertTrue(ParserError.isUnreachableSignal(URLError(.cannotFindHost)),      "-1003 is unreachable")
        XCTAssertTrue(ParserError.isUnreachableSignal(URLError(.notConnectedToInternet)), "-1009 is unreachable")
        XCTAssertFalse(ParserError.isUnreachableSignal(URLError(.timedOut)),           "-1001 is not")
        XCTAssertFalse(ParserError.isUnreachableSignal(URLError(.badServerResponse)),  "-1011 is not")
        XCTAssertFalse(ParserError.isUnreachableSignal(NSError(domain: "x", code: 1)), "non-URLError is not")
    }

    // MARK: - HTTP status → ParserError (extracted from parse() so it's testable without a URLSession)

    private func errorBody(_ error: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["error": error])
    }

    func testStatus200ProceedsToDecode() {
        XCTAssertNil(RemoteMedicationParser.error(forStatus: 200, body: Data()),
                     "a 200 returns nil so parse() decodes the body")
    }

    func testStatus500WithMissingKeyIsNotConfigured() {
        guard case .notConfigured = RemoteMedicationParser.error(forStatus: 500, body: errorBody("server_misconfigured")) else {
            return XCTFail("only the explicit server_misconfigured 500 is .notConfigured")
        }
    }

    /// AI1: a bare/uncaught 500 (e.g. a transient upstream fault) must NOT be mislabeled "AI isn't set
    /// up" — it maps to a transient `.server(500)` the user can retry.
    func testStatus500OtherwiseIsTransientServerError() {
        guard case .server(500) = RemoteMedicationParser.error(forStatus: 500, body: Data()) else {
            return XCTFail("a non-misconfigured 500 must be a transient .server(500), not .notConfigured")
        }
    }

    /// AI5: an over-length input (400 "too_long") surfaces the actionable message, not a generic code.
    func testStatus400TooLongIsSurfaced() {
        guard case .tooLong = RemoteMedicationParser.error(forStatus: 400, body: errorBody("too_long")) else {
            return XCTFail("a too_long 400 maps to .tooLong")
        }
        guard case .server(400) = RemoteMedicationParser.error(forStatus: 400, body: errorBody("invalid_request")) else {
            return XCTFail("other 400s stay a generic .server(400)")
        }
    }

    func testStatus422RefusalAndIncomplete() {
        guard case .refusal = RemoteMedicationParser.error(forStatus: 422, body: errorBody("refusal")) else {
            return XCTFail("refusal")
        }
        guard case .incomplete = RemoteMedicationParser.error(forStatus: 422, body: errorBody("incomplete")) else {
            return XCTFail("incomplete")
        }
    }

    /// AI2: a present-but-unknown `confidence` (a future server value) must default to `.low`, not fail
    /// the whole parse with `dataCorrupted`. `decodeIfPresent` alone was NOT lenient to unknown values.
    func testUnknownConfidenceStringDecodesToLowWithoutThrowing() throws {
        let json = Data("""
        {"medicines":[{"name":"Aspirin","dosage":null,"form":null,"frequency":null,"schedule":[],
        "quantity":null,"scheduleInferred":false,"uncertainFields":[],"confidence":"very-low",
        "requiresReview":true}]}
        """.utf8)
        let resp = try JSONDecoder().decode(ParseMedicationResponse.self, from: json)
        XCTAssertEqual(resp.medicines.first?.confidence, .low, "an unknown confidence falls back to .low")
    }
}
