import XCTest
@testable import Dose

/// Phase 1: the caregiver-share client builds the right requests, parses the result, maps errors, and
/// the local store persists/expires the one active share. A stub transport exercises the full path with
/// no live server.
final class CaregiverShareClientTests: XCTestCase {

    final class StubTransport: CaregiverShareTransport, @unchecked Sendable {
        let body: Data; let status: Int
        private(set) var lastRequest: URLRequest?
        init(_ body: Data, _ status: Int) { self.body = body; self.status = status }
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            lastRequest = request
            return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private let endpoint = URL(string: "https://x.supabase.co/functions/v1/caregiver-share")!
    private func sampleSnapshot() -> CaregiverShareSnapshot {
        CaregiverShareSnapshot(generatedAt: Date(timeIntervalSince1970: 1_800_000_000), patientLabel: "Mum",
                               rangeDays: 30, overallAdherencePercent: 90,
                               medicines: [], upcomingAppointments: [], metrics: [])
    }

    func testStatusErrorMapping() {
        XCTAssertNil(CaregiverShareClient.error(forStatus: 200))
        XCTAssertEqual(CaregiverShareClient.error(forStatus: 500), .notConfigured)
        XCTAssertEqual(CaregiverShareClient.error(forStatus: 429), .server(429))
    }

    func testCreateShareParsesResultAndPostsSnapshot() async throws {
        // Sub-second expiry, formatted WITH fractional seconds — exactly what the server sends
        // (JS `Date.toISOString()` always includes millis). Swift's built-in `.iso8601` strategy REJECTS
        // this, so this fixture fails-before / passes-after the flexible-decode fix.
        let expires = Date(timeIntervalSince1970: 1_800_000_000.5)
        let fmt = ISO8601DateFormatter(); fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = fmt.string(from: expires)
        let json = Data(#"{"token":"abc123","viewUrl":"https://x.supabase.co/functions/v1/caregiver-share?t=abc123","expiresAt":"\#(iso)"}"#.utf8)
        let stub = StubTransport(json, 200)
        let client = CaregiverShareClient(transport: stub, endpoint: endpoint, anonKey: "test-anon")

        let result = try await client.createShare(sampleSnapshot(), ttlDays: 7)
        XCTAssertEqual(result.token, "abc123")
        XCTAssertEqual(result.expiresAt, expires)

        XCTAssertEqual(stub.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(stub.lastRequest?.value(forHTTPHeaderField: "apikey"), "test-anon")
        let bodyStr = String(data: stub.lastRequest?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(bodyStr.contains("\"ttlDays\":7"), "ttl sent")
        XCTAssertTrue(bodyStr.contains("\"snapshot\""), "snapshot wrapped in the request body")
    }

    func testCreateShareServerErrorMaps() async {
        let client = CaregiverShareClient(transport: StubTransport(Data(), 502), endpoint: endpoint, anonKey: "k")
        do { _ = try await client.createShare(sampleSnapshot()); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? CaregiverShareError, .server(502)) }
    }

    func testRevokeSendsDeleteWithToken() async throws {
        let stub = StubTransport(Data(#"{"ok":true}"#.utf8), 200)
        let client = CaregiverShareClient(transport: stub, endpoint: endpoint, anonKey: "k")
        try await client.revoke(token: "tok9")
        XCTAssertEqual(stub.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(stub.lastRequest?.url?.query, "t=tok9")
    }

    func testNotConfiguredWhenNoEndpoint() async {
        let client = CaregiverShareClient(transport: StubTransport(Data(), 200), endpoint: nil, anonKey: nil)
        do { _ = try await client.createShare(sampleSnapshot()); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? CaregiverShareError, .notConfigured) }
    }

    func testStorePersistsAndExpires() {
        CaregiverShareStore.clear()
        defer { CaregiverShareStore.clear() }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let live = CaregiverShareResult(token: "t", viewUrl: URL(string: "https://x/y?t=t")!,
                                        expiresAt: now.addingTimeInterval(86_400))
        CaregiverShareStore.current = live
        XCTAssertEqual(CaregiverShareStore.current, live, "round-trips through UserDefaults")
        XCTAssertEqual(CaregiverShareStore.active(now: now)?.token, "t")

        let expired = CaregiverShareResult(token: "e", viewUrl: URL(string: "https://x/y?t=e")!,
                                           expiresAt: now.addingTimeInterval(-1))
        CaregiverShareStore.current = expired
        XCTAssertNil(CaregiverShareStore.active(now: now), "an expired share is treated as none")

        CaregiverShareStore.clear()
        XCTAssertNil(CaregiverShareStore.current)
    }
}
