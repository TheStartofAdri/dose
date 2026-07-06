import SwiftUI
import UIKit

/// Inline, non-nagging notice shown when reminders can't actually reach the user — either the OS
/// permission is off (nothing will fire) or the schedule overflowed iOS's 64-pending cap (some
/// reminders were dropped). Mirrors the History cards' style. Reads `NotificationStatus.shared`, so
/// it appears/updates as that state changes. Gate the call site on `NotificationStatus.shared.hasNotice`
/// so it (and any surrounding padding) takes no space when reminders are healthy.
struct NotificationNoticeBanner: View {
    /// `.card` = standalone (Today, with `.doseCard()`); `.plain` = inside a Form row (Settings).
    enum Style { case card, plain }
    var style: Style = .card

    private let status = NotificationStatus.shared

    var body: some View {
        if status.remindersDisabled {
            banner(icon: "bell.slash.fill", tint: .red,
                   title: "Reminders are off",
                   message: "Turn on notifications so Dose can remind you to take your medicine.",
                   actionTitle: "Open Settings", action: openSettings)
        } else if status.schedulingTruncated {
            banner(icon: "exclamationmark.triangle.fill", tint: .orange,
                   title: "Some reminders couldn't be scheduled",
                   message: "You have more active reminders than iOS allows at once, so the soonest ones were kept. Consider fewer medicines or times.",
                   actionTitle: nil, action: nil)
        }
    }

    @ViewBuilder
    private func banner(icon: String, tint: Color, title: String, message: String,
                        actionTitle: String?, action: (() -> Void)?) -> some View {
        let row = HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        if style == .card { row.doseCard() } else { row }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
