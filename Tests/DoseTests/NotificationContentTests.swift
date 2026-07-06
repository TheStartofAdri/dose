import XCTest
import UserNotifications
@testable import Dose

/// Item 1: every dose-reminder content must be delivered `.timeSensitive` so Focus / Do Not Disturb /
/// Sleep can't silence a medication reminder. All three reminder kinds (base, windowed/escalation,
/// snooze) route through `NotificationScheduler.makeContent`, so testing the factory covers them all.
@MainActor
final class NotificationContentTests: XCTestCase {
    func testBaseReminderContentIsTimeSensitive() {
        let content = NotificationScheduler.makeContent(
            name: "Vitamin D", dosage: "1000 IU", userInfo: ["kind": "base"])
        XCTAssertEqual(content.interruptionLevel, .timeSensitive)
        XCTAssertEqual(content.categoryIdentifier, NotificationScheduler.categoryID)
        XCTAssertEqual(content.title, "Time for Vitamin D")
        XCTAssertEqual(content.body, "Take 1000 IU")
    }

    func testEscalationContentIsTimeSensitive() {
        let content = NotificationScheduler.makeContent(
            name: "Amoxicillin", dosage: nil, escalation: true, userInfo: ["kind": "escalation"])
        XCTAssertEqual(content.interruptionLevel, .timeSensitive)
        XCTAssertEqual(content.categoryIdentifier, NotificationScheduler.categoryID)
        XCTAssertEqual(content.title, "Still time for Amoxicillin")
        XCTAssertEqual(content.body, "Tap to mark as taken.")
    }

    func testSnoozeShapedContentIsTimeSensitive() {
        let content = NotificationScheduler.makeContent(
            name: "Magnesium", dosage: "400 mg", userInfo: ["kind": "snooze"])
        XCTAssertEqual(content.interruptionLevel, .timeSensitive)
        XCTAssertEqual(content.categoryIdentifier, NotificationScheduler.categoryID)
    }

    // Feature A: a lead-time heads-up is time-sensitive and uses the countdown title.
    func testLeadTimeContentIsTimeSensitiveWithCountdownTitle() {
        let content = NotificationScheduler.makeContent(
            name: "Aspirin", dosage: "100 mg", leadMinutes: 15, userInfo: ["kind": "leadtime"])
        XCTAssertEqual(content.interruptionLevel, .timeSensitive)
        XCTAssertEqual(content.title, "Aspirin coming up in 15 min")
        XCTAssertEqual(content.categoryIdentifier, NotificationScheduler.categoryID)
    }
}
