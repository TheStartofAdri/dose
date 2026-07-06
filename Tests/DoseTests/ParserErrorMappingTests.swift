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
}
