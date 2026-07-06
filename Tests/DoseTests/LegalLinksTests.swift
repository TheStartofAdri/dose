import XCTest
@testable import Dose

/// `LegalLinks` is the single source of truth for the app's published legal URLs — both the paywall's
/// App-Review-required Terms/Privacy links and the Settings "About" rows resolve to these exact constants.
/// Pinning them here guards the privacy URL from silently regressing to a placeholder (the original audit
/// finding S1, a hard App Review reject) and keeps the two surfaces from drifting apart.
final class LegalLinksTests: XCTestCase {
    func testPrivacyURLIsThePublishedHTTPSPolicy() {
        XCTAssertEqual(LegalLinks.privacy.absoluteString, "https://dose-med-tracker.com/privacy")
        XCTAssertEqual(LegalLinks.privacy.scheme, "https", "privacy policy must be served over HTTPS")
    }

    func testTermsURLIsAppleStandardEULAOverHTTPS() {
        XCTAssertEqual(LegalLinks.terms.absoluteString,
                       "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        XCTAssertEqual(LegalLinks.terms.scheme, "https")
    }
}
