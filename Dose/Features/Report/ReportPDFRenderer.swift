import UIKit

/// Renders a `ReportData` to PDF `Data` on-device via `UIGraphicsPDFRenderer`. Multi-page with a
/// disclaimer footer on every page. Pure rendering — no data access here.
enum ReportPDFRenderer {
    static func render(_ data: ReportData) -> Data {
        let pageW: CGFloat = 612, pageH: CGFloat = 792, margin: CGFloat = 48   // US Letter
        let contentW = pageW - margin * 2
        let contentBottom = pageH - margin - 24                                // leave room for the footer
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))

        let dateOnly = DateFormatter(); dateOnly.dateStyle = .medium
        let dateTime = DateFormatter(); dateTime.dateStyle = .medium; dateTime.timeStyle = .short

        return renderer.pdfData { ctx in
            var y: CGFloat = margin

            func drawFooter() {
                let text = "Self-reported adherence from Dose — not a medical record."
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.secondaryLabel,
                ]
                (text as NSString).draw(at: CGPoint(x: margin, y: pageH - margin + 4), withAttributes: attrs)
            }
            func newPage() { ctx.beginPage(); drawFooter(); y = margin }
            func ensure(_ height: CGFloat) { if y + height > contentBottom { newPage() } }

            func draw(_ string: String, font: UIFont, color: UIColor = .label, spacingAfter: CGFloat = 0) {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let size = (string as NSString).boundingRect(
                    with: CGSize(width: contentW, height: .greatestFiniteMagnitude),
                    options: .usesLineFragmentOrigin, attributes: attrs, context: nil).size
                ensure(size.height)
                (string as NSString).draw(with: CGRect(x: margin, y: y, width: contentW, height: ceil(size.height)),
                                          options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
                y += ceil(size.height) + spacingAfter
            }

            func color(for day: DayAdherence) -> UIColor {
                if day.taken == 0 && day.skipped == 0 && day.missed == 0 { return DoseColors.UI.none }   // none scheduled
                if day.missed > 0 && day.taken > 0 { return DoseColors.UI.due }                          // partial
                if day.missed > 0 { return DoseColors.UI.missed }
                if day.taken > 0 { return DoseColors.UI.taken }
                return DoseColors.UI.neutralSolid                                                        // skipped only
            }

            func drawStrip(_ days: [DayAdherence]) {
                let cell: CGFloat = 9, pitch: CGFloat = 12
                let perRow = max(1, Int(contentW / pitch))
                var i = 0
                while i < days.count {
                    ensure(cell + 4)
                    var x = margin
                    var drawn = 0
                    while drawn < perRow && i < days.count {
                        let rect = CGRect(x: x, y: y, width: cell, height: cell)
                        color(for: days[i]).setFill()
                        UIBezierPath(roundedRect: rect, cornerRadius: 2).fill()
                        x += pitch; i += 1; drawn += 1
                    }
                    y += cell + 4
                }
            }

            func drawLegend() {
                ensure(18)
                let items: [(UIColor, String)] = [
                    (DoseColors.UI.taken, "Taken"), (DoseColors.UI.neutralSolid, "Skipped"),
                    (DoseColors.UI.missed, "Missed"), (DoseColors.UI.due, "Partial"), (DoseColors.UI.none, "None"),
                ]
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.secondaryLabel,
                ]
                var x = margin
                for (swatch, label) in items {
                    swatch.setFill()
                    UIBezierPath(roundedRect: CGRect(x: x, y: y, width: 9, height: 9), cornerRadius: 2).fill()
                    x += 12
                    (label as NSString).draw(at: CGPoint(x: x, y: y - 1), withAttributes: attrs)
                    x += (label as NSString).size(withAttributes: attrs).width + 14
                }
                y += 16
            }

            // MARK: page 1 — title + range
            newPage()
            draw("Adherence Report", font: .boldSystemFont(ofSize: 22), spacingAfter: 2)
            draw("\(dateOnly.string(from: data.rangeStart)) – \(dateOnly.string(from: data.rangeEnd))",
                 font: .systemFont(ofSize: 12), color: .secondaryLabel)
            draw("Generated \(dateTime.string(from: data.generatedAt))",
                 font: .systemFont(ofSize: 10), color: .secondaryLabel, spacingAfter: 12)

            // Summary header — what a first-time reader needs to gauge how much was tracked.
            let s = data.summary
            draw("\(s.overallRatePercent.map { "\($0)%" } ?? "—") overall adherence",
                 font: .boldSystemFont(ofSize: 16), spacingAfter: 1)
            draw("\(s.periodDays) days tracked   ·   \(s.scheduled) scheduled   ·   \(s.taken) taken / \(s.skipped) skipped / \(s.missed) missed",
                 font: .systemFont(ofSize: 11), color: .secondaryLabel, spacingAfter: 6)
            // Inline explanation of the day strips, near the data (not only the legend).
            draw("Below, each medicine shows one square per day — green = taken, grey = skipped, red = missed.",
                 font: .systemFont(ofSize: 10), color: .secondaryLabel, spacingAfter: 16)

            // Body — EVERY explicitly-selected medicine appears (never silently dropped). A med with
            // nothing recorded in range is shown as such rather than omitted.
            if data.lines.isEmpty {
                draw("No medicines selected.", font: .systemFont(ofSize: 12), color: .secondaryLabel)
            }
            for line in data.lines {
                ensure(70)
                draw(line.dosage.map { "\(line.name) · \($0)" } ?? line.name,
                     font: .boldSystemFont(ofSize: 15), spacingAfter: 1)
                if line.hasScheduledDoses {
                    let counted = line.taken + line.missed
                    let pct = line.ratePercent.map { "\($0)%" } ?? "—"
                    var summary = "\(pct) — \(line.taken) of \(counted) doses taken"
                    if line.skipped > 0 { summary += "  ·  \(line.skipped) skipped" }
                    draw(summary, font: .systemFont(ofSize: 12), color: .secondaryLabel, spacingAfter: 6)
                    drawStrip(line.days)
                } else {
                    draw("No doses recorded in this period.", font: .systemFont(ofSize: 12),
                         color: .secondaryLabel, spacingAfter: 0)
                }
                y += 16
            }

            drawLegend()
        }
    }
}
