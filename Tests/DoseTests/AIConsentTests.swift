import XCTest
@testable import Dose

/// The AI-consent flag (`SettingsKeys.aiConsentGiven`) is the single source of truth for the one-time
/// "Use AI to read this?" prompt. The Settings "Reset AI permission" row revokes it; this pins that
/// revoking resets the flag AND re-arms the prompt (`needsPrompt` is exactly the views' gate condition).
final class AIConsentTests: XCTestCase {
    override func setUp() { super.setUp(); AIConsent.revoke() }   // known baseline
    override func tearDown() { AIConsent.revoke(); super.tearDown() }

    func testRevokeResetsFlagAndReArmsPrompt() {
        AIConsent.grant()
        XCTAssertTrue(AIConsent.isGranted, "granting sets the flag")
        XCTAssertFalse(AIConsent.needsPrompt, "while granted, the next AI parse does NOT prompt")

        AIConsent.revoke()   // what the Settings "Reset AI permission" row does
        XCTAssertFalse(AIConsent.isGranted, "revoke resets the consent flag")
        XCTAssertTrue(AIConsent.needsPrompt, "revoke re-arms the one-time prompt for the next AI parse")
    }

    func testDefaultStateNeedsPrompt() {
        XCTAssertTrue(AIConsent.needsPrompt, "with no consent granted, the prompt will show")
    }
}
