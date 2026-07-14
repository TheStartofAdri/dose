import XCTest
@testable import Dose

/// Phase 4: the pure "what changed" highlight rules + correlation. Observations only — no medical claims.
final class InsightsEngineTests: XCTestCase {
    private func h(streak: Int = 0, missed: Int = 0, missedLast: Int = 0,
                  adh: Double? = nil, adhLast: Double? = nil, metrics: [MetricWeekly] = []) -> [Highlight] {
        InsightsEngine.highlights(currentStreak: streak, missedThisWeek: missed, missedLastWeek: missedLast,
                                  adherenceThisWeek: adh, adherenceLastWeek: adhLast, metrics: metrics)
    }

    func testStreakHighlightOnlyAtThreshold() {
        XCTAssertTrue(h(streak: 3).contains { $0.title.contains("3-day streak") })
        XCTAssertFalse(h(streak: 2).contains { $0.title.contains("streak") })
    }

    func testAdherenceUpDownAndFlat() {
        XCTAssertTrue(h(adh: 0.9, adhLast: 0.8).contains { $0.title.contains("Adherence up to 90%") && $0.tone == .positive })
        XCTAssertTrue(h(adh: 0.7, adhLast: 0.85).contains { $0.title.contains("dipped to 70%") && $0.tone == .attention })
        XCTAssertFalse(h(adh: 0.82, adhLast: 0.80).contains { $0.title.contains("Adherence") }, "a small change is not surfaced")
    }

    func testMissedDosesFewerVsMore() {
        XCTAssertTrue(h(missed: 1, missedLast: 3).contains { $0.title.contains("Fewer missed") && $0.tone == .positive })
        XCTAssertTrue(h(missed: 3, missedLast: 1).contains { $0.title.contains("3 missed doses") && $0.tone == .attention })
        XCTAssertFalse(h(missed: 0, missedLast: 2).contains { $0.title.contains("missed") }, "no missed this week → no missed highlight")
    }

    func testMetricTrendRulesAndThresholds() {
        let painUp = MetricWeekly(name: "Pain", unit: nil, isSeverity: true, thisWeekAvg: 6, lastWeekAvg: 4, daysLoggedLast7: 4)
        XCTAssertTrue(h(metrics: [painUp]).contains { $0.title.contains("Pain trending up") && $0.tone == .attention })

        let tooFewDays = MetricWeekly(name: "Weight", unit: "kg", isSeverity: false, thisWeekAvg: 75, lastWeekAvg: 72, daysLoggedLast7: 1)
        XCTAssertTrue(h(metrics: [tooFewDays]).isEmpty, "needs ≥2 days logged")

        let tinyChange = MetricWeekly(name: "Weight", unit: "kg", isSeverity: false, thisWeekAvg: 72.1, lastWeekAvg: 72, daysLoggedLast7: 5)
        XCTAssertTrue(h(metrics: [tinyChange]).isEmpty, "sub-threshold change is not surfaced")

        let realChange = MetricWeekly(name: "Weight", unit: "kg", isSeverity: false, thisWeekAvg: 75, lastWeekAvg: 72, daysLoggedLast7: 5)
        XCTAssertTrue(h(metrics: [realChange]).contains { $0.title.contains("Weight trending up") && $0.tone == .neutral })
    }

    func testPearson() {
        XCTAssertEqual(InsightsEngine.pearson([1, 2, 3, 4], [2, 4, 6, 8])!, 1.0, accuracy: 0.0001)
        XCTAssertEqual(InsightsEngine.pearson([1, 2, 3, 4], [8, 6, 4, 2])!, -1.0, accuracy: 0.0001)
        XCTAssertNil(InsightsEngine.pearson([1, 2], [1, 2]), "fewer than 3 pairs")
        XCTAssertNil(InsightsEngine.pearson([5, 5, 5], [1, 2, 3]), "no variance in one series")
    }
}
