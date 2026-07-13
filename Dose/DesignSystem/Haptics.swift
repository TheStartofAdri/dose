import UIKit

/// Haptic feedback for primary actions. Execution Mode fires `success` on TAKE; lighter taps for
/// snooze/skip.
enum Haptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// A failure buzz — used when a dose action couldn't be saved, so the negative outcome is felt, not
    /// silently mistaken for the usual success tap.
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
