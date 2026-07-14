import Foundation

/// A short, actionable observation for the Insights tab. Descriptive — an observation, never a diagnosis.
struct Highlight: Identifiable, Hashable, Sendable {
    enum Tone: Sendable { case positive, attention, neutral }
    let icon: String
    let title: String
    let tone: Tone
    var id: String { icon + "|" + title }
}

/// One tracked metric's weekly aggregates — computed by the view layer and fed to the pure engine.
struct MetricWeekly: Sendable, Equatable {
    let name: String
    let unit: String?
    let isSeverity: Bool
    let thisWeekAvg: Double?
    let lastWeekAvg: Double?
    let daysLoggedLast7: Int
}

/// Rule-based "what changed" highlights + a simple correlation. Pure, so it's fully unit-testable and the
/// same logic can drive both the Insights tab and a weekly digest. Observations only — no medical claims.
enum InsightsEngine {
    /// The week-over-week highlights, most-actionable first (attention before positive before neutral is
    /// NOT enforced; order is streak → adherence → missed → metric trends, which reads naturally).
    static func highlights(currentStreak: Int,
                           missedThisWeek: Int, missedLastWeek: Int,
                           adherenceThisWeek: Double?, adherenceLastWeek: Double?,
                           metrics: [MetricWeekly]) -> [Highlight] {
        var out: [Highlight] = []

        if currentStreak >= 3 {
            out.append(.init(icon: "flame.fill", title: "\(currentStreak)-day streak — keep it going", tone: .positive))
        }

        if let this = adherenceThisWeek, let last = adherenceLastWeek {
            let t = pct(this), l = pct(last)
            if t >= l + 5 {
                out.append(.init(icon: "arrow.up.right", title: "Adherence up to \(t)% this week", tone: .positive))
            } else if t <= l - 5 {
                out.append(.init(icon: "arrow.down.right", title: "Adherence dipped to \(t)% this week", tone: .attention))
            }
        }

        if missedThisWeek > 0 {
            if missedThisWeek < missedLastWeek {
                out.append(.init(icon: "checkmark.circle",
                                 title: "Fewer missed doses than last week (\(missedThisWeek) vs \(missedLastWeek))",
                                 tone: .positive))
            } else {
                out.append(.init(icon: "exclamationmark.circle",
                                 title: "\(missedThisWeek) missed dose\(missedThisWeek == 1 ? "" : "s") this week",
                                 tone: .attention))
            }
        }

        for metric in metrics {
            guard metric.daysLoggedLast7 >= 2, let this = metric.thisWeekAvg, let last = metric.lastWeekAvg else { continue }
            let delta = this - last
            guard abs(delta) >= changeThreshold(for: metric) else { continue }
            let up = delta > 0
            let unit = metric.unit.map { " \($0)" } ?? ""
            out.append(.init(icon: up ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                             title: "\(metric.name) trending \(up ? "up" : "down") (\(fmt(last))\(unit) → \(fmt(this))\(unit))",
                             // A rising symptom warrants attention; a moving vital is just neutral information.
                             tone: metric.isSeverity && up ? .attention : .neutral))
        }

        return out
    }

    /// Pearson correlation over paired values; `nil` when there are fewer than 3 pairs, the lengths differ,
    /// or either series has zero variance.
    static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 3 else { return nil }
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var num = 0.0, dx = 0.0, dy = 0.0
        for i in xs.indices {
            let a = xs[i] - mx, b = ys[i] - my
            num += a * b; dx += a * a; dy += b * b
        }
        guard dx > 0, dy > 0 else { return nil }
        return num / (dx.squareRoot() * dy.squareRoot())
    }

    private static func pct(_ rate: Double) -> Int { Int((rate * 100).rounded()) }
    private static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    /// The minimum change worth surfacing: 1 point for a 0–10 symptom, else ~3% of the prior average.
    private static func changeThreshold(for metric: MetricWeekly) -> Double {
        metric.isSeverity ? 1.0 : max(0.1, abs(metric.lastWeekAvg ?? 1) * 0.03)
    }
}
