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
}
