import XCTest
import UIKit
@testable import Dose

final class ReportTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let medA = UUID()
    private let medB = UUID()

    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: min))!
    }
    private func med(_ id: UUID, _ name: String, createdAt: Date, endDate: Date? = nil) -> MedicineSnapshot {
        MedicineSnapshot(id: id, name: name, dosage: "5 mg",
                         rules: [DoseSlotRule(hour: 8, minute: 0)], createdAt: createdAt, endDate: endDate)
    }
    private func taken(_ id: UUID, _ y: Int, _ mo: Int, _ d: Int) -> DoseLogSnapshot {
        DoseLogSnapshot(medicineID: id, scheduledFor: at(y, mo, d, 8), action: .taken, actionedAt: at(y, mo, d, 8))
    }
    private func skipped(_ id: UUID, _ y: Int, _ mo: Int, _ d: Int) -> DoseLogSnapshot {
        DoseLogSnapshot(medicineID: id, scheduledFor: at(y, mo, d, 8), action: .skipped, actionedAt: at(y, mo, d, 8))
    }

    // MARK: - Custom range clamps a future end (B6)

    /// A custom range whose `to` is in the future must clamp to `now`, so empty not-yet-happened days
    /// don't inflate the report's "days tracked". FAIL-BEFORE: `to` was returned as-is.
    func testCustomRangeClampsFutureEndAtNow() {
        let now = at(2026, 6, 16, 12)
        let (from, to) = ReportRange.custom(from: at(2026, 6, 10), to: at(2026, 6, 20)).resolved(now: now, calendar: cal)
        XCTAssertEqual(from, at(2026, 6, 10))
        XCTAssertEqual(to, now, "a future end clamps to now")
    }

    func testCustomRangeStillOrdersEndpointsAndKeepsPastRanges() {
        let now = at(2026, 6, 16, 12)
        // Reversed, fully in the past → ordered, unchanged by the clamp.
        let (from, to) = ReportRange.custom(from: at(2026, 6, 12), to: at(2026, 6, 8)).resolved(now: now, calendar: cal)
        XCTAssertEqual(from, at(2026, 6, 8))
        XCTAssertEqual(to, at(2026, 6, 12))
    }

    // MARK: - Seam

    @MainActor
    func testEntitlementSeamReflectsSubscription() {
        // `Entitlements.isPremium` now reads the live StoreKit subscription state via `SubscriptionStore`.
        SubscriptionStore.shared.setPremiumForTesting(true)
        XCTAssertTrue(Entitlements.isPremium, "report export is available with an active subscription")
        SubscriptionStore.shared.setPremiumForTesting(false)
        XCTAssertFalse(Entitlements.isPremium, "report export gates when lapsed")
        SubscriptionStore.shared.setPremiumForTesting(true)   // leave unlocked for any premium-dependent checks
    }

    // MARK: - AdherenceCalculator range overload

    func testRangeOverloadCounts() {
        let now = at(2026, 6, 16, 23)
        let a = med(medA, "A", createdAt: at(2026, 6, 1))
        let logs = [taken(medA, 2026, 6, 10), taken(medA, 2026, 6, 11), taken(medA, 2026, 6, 12),
                    skipped(medA, 2026, 6, 13)]   // 6/14,15,16 untaken → missed
        let days = AdherenceCalculator.days(medicines: [a], logs: logs, from: at(2026, 6, 10), to: now, now: now, calendar: cal)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.reduce(0) { $0 + $1.taken }, 3)
        XCTAssertEqual(days.reduce(0) { $0 + $1.skipped }, 1)
        XCTAssertEqual(days.reduce(0) { $0 + $1.missed }, 3)
    }

    // MARK: - ReportBuilder

    func testPerMedBreakdownAndMatchesCalculator() {
        let now = at(2026, 6, 16, 23)
        let a = med(medA, "A", createdAt: at(2026, 6, 1))
        let b = med(medB, "B", createdAt: at(2026, 6, 1))
        let logs = [taken(medA, 2026, 6, 14), taken(medA, 2026, 6, 15), taken(medA, 2026, 6, 16),
                    skipped(medB, 2026, 6, 16)]
        let data = ReportBuilder.build(medicines: [a, b], logs: logs, range: .last7, now: now, generatedAt: now, calendar: cal)

        XCTAssertEqual(data.lines.count, 2)
        let lineA = try! XCTUnwrap(data.lines.first { $0.name == "A" })
        XCTAssertEqual(lineA.taken, 3); XCTAssertEqual(lineA.missed, 4); XCTAssertEqual(lineA.skipped, 0)
        XCTAssertEqual(lineA.ratePercent, 43)   // round(3/7 * 100)

        let lineB = try! XCTUnwrap(data.lines.first { $0.name == "B" })
        XCTAssertEqual(lineB.taken, 0); XCTAssertEqual(lineB.missed, 6); XCTAssertEqual(lineB.skipped, 1)
        XCTAssertEqual(lineB.ratePercent, 0, "a skip is neutral, not a take")

        // Numbers equal AdherenceCalculator over the same window, by construction.
        let (from, to) = ReportRange.last7.resolved(now: now, calendar: cal)
        let seriesA = AdherenceCalculator.days(medicines: [a], logs: logs, from: from, to: to, now: now, calendar: cal)
        XCTAssertEqual(lineA.ratePercent, AdherenceCalculator.rate(seriesA).map { Int(($0 * 100).rounded()) })
    }

    func testMedSubsetFilters() {
        let now = at(2026, 6, 16, 23)
        let a = med(medA, "A", createdAt: at(2026, 6, 1))
        let data = ReportBuilder.build(medicines: [a], logs: [taken(medA, 2026, 6, 16)],
                                       range: .last7, now: now, generatedAt: now, calendar: cal)
        XCTAssertEqual(data.lines.count, 1)
        XCTAssertEqual(data.lines.first?.name, "A")
    }

    func testDateRangeExcludesOutOfRangeLogs() {
        let now = at(2026, 6, 16, 23)
        let a = med(medA, "A", createdAt: at(2026, 5, 1))
        let logs = [taken(medA, 2026, 6, 1), taken(medA, 2026, 6, 16)]   // 6/1 is outside last-7
        let line = try! XCTUnwrap(ReportBuilder.build(medicines: [a], logs: logs, range: .last7,
                                                      now: now, generatedAt: now, calendar: cal).lines.first)
        XCTAssertEqual(line.taken, 1, "only the in-range taken dose counts")
        XCTAssertEqual(line.missed, 6)
        XCTAssertEqual(line.ratePercent, 14)   // round(1/7 * 100)
    }

    // MARK: - Summary + app-match

    func testSummaryTotalsAndOmitsEmptyMed() {
        let now = at(2026, 6, 16, 12)
        let a = med(medA, "A", createdAt: at(2026, 6, 1))
        let b = med(medB, "B (future)", createdAt: at(2026, 7, 1))   // created after the range → empty
        let logs = (11...16).map { taken(medA, 2026, 6, $0) }        // 6/10 missed, 6/11–16 taken
        let data = ReportBuilder.build(medicines: [a, b], logs: logs, range: .last7, now: now, generatedAt: now, calendar: cal)

        XCTAssertEqual(data.summary.periodDays, 7)
        XCTAssertEqual(data.summary.taken, 6)
        XCTAssertEqual(data.summary.missed, 1)
        XCTAssertEqual(data.summary.scheduled, 7)       // 6 taken + 1 missed (B contributes nothing)
        XCTAssertEqual(data.summary.overallRatePercent, 86)   // round(6/7 * 100)

        // B has no scheduled doses in range → omitted from the body.
        XCTAssertEqual(data.lines.count, 2)
        XCTAssertFalse(data.lines.first { $0.name == "B (future)" }!.hasScheduledDoses)
        XCTAssertEqual(data.lines.filter { $0.hasScheduledDoses }.map(\.name), ["A"])
    }

    /// The report's overall % must equal what the in-app History screen shows for the same med over
    /// the same 7-day period (History computes via `days(now:days:7)` → `rate`).
    func testReportPercentMatchesInAppHistory() {
        let now = at(2026, 6, 16, 12)
        let a = med(medA, "A", createdAt: at(2026, 6, 1))
        let logs = (11...16).map { taken(medA, 2026, 6, $0) }   // 6 of 7 → 86%
        let report = ReportBuilder.build(medicines: [a], logs: logs, range: .last7, now: now, generatedAt: now, calendar: cal)

        let appSeries = AdherenceCalculator.days(medicines: [a], logs: logs, now: now, days: 7, calendar: cal)
        let appPercent = AdherenceCalculator.rate(appSeries).map { Int(($0 * 100).rounded()) }

        XCTAssertEqual(report.summary.overallRatePercent, appPercent,
                       "report overall % must match the in-app History 7-day %")
        XCTAssertEqual(report.summary.overallRatePercent, 86)
        XCTAssertEqual(appPercent, 86)
    }

    /// Item 1 parity on a BUG-TRIGGERING med (created this afternoon, taken this morning) — the case
    /// the old calculator zeroed. Report % and in-app History % must agree AT the correct number (100%).
    func testReportAndHistoryAgreeOnBugTriggeringMed() throws {
        let createdAt = at(2026, 6, 16, 14, 0)        // created 2pm today
        let now = at(2026, 6, 16, 18, 0)
        let med = MedicineSnapshot(id: medA, name: "Created Today", dosage: "5 mg",
                                   rules: [DoseSlotRule(hour: 8, minute: 0)], createdAt: createdAt)
        let logs = [taken(medA, 2026, 6, 16)]         // taken at 08:00, before the 2pm creation

        let report = ReportBuilder.build(medicines: [med], logs: logs, range: .last7, now: now, generatedAt: now, calendar: cal)
        let line = try XCTUnwrap(report.lines.first)
        XCTAssertTrue(line.hasScheduledDoses, "the med appears in the body, not omitted")
        XCTAssertEqual(line.taken, 1)
        XCTAssertEqual(line.ratePercent, 100)

        // In-app History path (days(now:days:7) → rate) — must equal the report at the correct number.
        let appSeries = AdherenceCalculator.days(medicines: [med], logs: logs, now: now, days: 7, calendar: cal)
        let appPercent = AdherenceCalculator.rate(appSeries).map { Int(($0 * 100).rounded()) }
        XCTAssertEqual(line.ratePercent, appPercent, "report % == in-app History %")
        XCTAssertEqual(appPercent, 100, "History now counts the take too (was 0 before the fix)")
    }

    // MARK: - PDF

    func testPDFIsValidNonEmpty() {
        let now = at(2026, 6, 16, 23)
        let a = med(medA, "Vitamin D", createdAt: at(2026, 6, 1))
        let data = ReportBuilder.build(medicines: [a], logs: [taken(medA, 2026, 6, 16)],
                                       range: .last7, now: now, generatedAt: now, calendar: cal)
        let pdf = ReportPDFRenderer.render(data)
        XCTAssertGreaterThan(pdf.count, 800, "PDF should contain real content")
        XCTAssertEqual(String(data: pdf.prefix(5), encoding: .ascii), "%PDF-")
    }

    /// Rasterizes the generated PDF's first page and attaches it so the content can be eyeballed.
    func testRenderedPDFFirstPageAttachment() throws {
        let now = at(2026, 6, 16, 23)
        let a = med(medA, "Vitamin D", createdAt: at(2026, 5, 20))
        let b = med(medB, "Amoxicillin", createdAt: at(2026, 6, 8))
        var logs: [DoseLogSnapshot] = []
        for d in 1...16 where d != 4 && d != 9 { logs.append(taken(medA, 2026, 6, d)) }  // A mostly taken
        logs.append(skipped(medA, 2026, 6, 9))                                            // one skip
        for d in 9...16 where d != 12 && d != 14 { logs.append(taken(medB, 2026, 6, d)) } // B with 2 misses
        let data = ReportBuilder.build(medicines: [a, b], logs: logs, range: .last30, now: now, generatedAt: now, calendar: cal)
        let pdf = ReportPDFRenderer.render(data)

        let provider = try XCTUnwrap(CGDataProvider(data: pdf as CFData))
        let doc = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(doc.page(at: 1))
        let rect = page.getBoxRect(.mediaBox)
        let image = UIGraphicsImageRenderer(size: rect.size).image { ctx in
            UIColor.white.set(); ctx.fill(rect)
            ctx.cgContext.translateBy(x: 0, y: rect.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            ctx.cgContext.drawPDFPage(page)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "report-pdf-page1"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Item 1 (renderer) + item 3 (format): a report where the user explicitly selected THREE meds,
    /// one of which has no doses in the period. Proves the zero-dose med is rendered ("No doses
    /// recorded in this period") rather than silently dropped, and the per-med lines read clearly.
    /// Rasterizes the page so the doctor-facing layout can be eyeballed in the attachment.
    func testRenderedPDFShowsEverySelectedMedIncludingZeroDose() throws {
        let medC = UUID()
        let now = at(2026, 6, 16, 23)
        let a = med(medA, "Vitamin D", createdAt: at(2026, 5, 20))
        let b = med(medB, "Amoxicillin", createdAt: at(2026, 6, 8))
        // A finished course the user still selected: its treatment ended before this report window, so
        // it has NO scheduled doses in range — the realistic "No doses recorded in this period" case.
        let c = med(medC, "Ibuprofen", createdAt: at(2026, 4, 1), endDate: at(2026, 5, 10))
        var logs: [DoseLogSnapshot] = []
        for d in 1...16 where d != 4 { logs.append(taken(medA, 2026, 6, d)) }   // A mostly taken
        for d in 9...16 where d != 12 { logs.append(taken(medB, 2026, 6, d)) }  // B taken, a couple misses
        // medC: ended before the window → no slots, no logs.

        let data = ReportBuilder.build(medicines: [a, b, c], logs: logs, range: .last30, now: now, generatedAt: now, calendar: cal)

        // The data layer keeps all three selected meds; the zero-dose one is flagged, not dropped.
        XCTAssertEqual(data.lines.map(\.name), ["Vitamin D", "Amoxicillin", "Ibuprofen"])
        let ibuprofen = try XCTUnwrap(data.lines.first { $0.name == "Ibuprofen" })
        XCTAssertFalse(ibuprofen.hasScheduledDoses, "the zero-dose med has nothing recorded")
        XCTAssertEqual(ibuprofen.taken, 0)

        let pdf = ReportPDFRenderer.render(data)
        let provider = try XCTUnwrap(CGDataProvider(data: pdf as CFData))
        let doc = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(doc.page(at: 1))
        let rect = page.getBoxRect(.mediaBox)
        let image = UIGraphicsImageRenderer(size: rect.size).image { ctx in
            UIColor.white.set(); ctx.fill(rect)
            ctx.cgContext.translateBy(x: 0, y: rect.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            ctx.cgContext.drawPDFPage(page)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "report-pdf-all-selected-meds"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
