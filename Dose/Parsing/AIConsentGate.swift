import SwiftUI

/// Single source of truth for the one-time AI-consent flag (`SettingsKeys.aiConsentGiven`). The views'
/// `@AppStorage` gate, the Settings "Reset AI permission" row, the `DoseApp` test seeds, and the tests
/// all read/write this **one** key — no parallel state. `needsPrompt` is exactly the views' gate
/// condition (`!granted`), so revoking re-arms the prompt for the next AI parse.
enum AIConsent {
    static var isGranted: Bool { UserDefaults.standard.bool(forKey: SettingsKeys.aiConsentGiven) }
    /// True when the next AI parse must show the consent prompt (never granted, or revoked in Settings).
    static var needsPrompt: Bool { !isGranted }
    static func grant() { UserDefaults.standard.set(true, forKey: SettingsKeys.aiConsentGiven) }
    static func revoke() { UserDefaults.standard.set(false, forKey: SettingsKeys.aiConsentGiven) }
}

/// One-time explicit consent before the first AI parse sends a user's text (or a photo's OCR'd text)
/// off-device to the AI service (Anthropic). Apple 5.1.2(i) (Nov 2025) requires disclosure **and**
/// explicit permission before sharing personal data with third-party AI — the privacy policy is the
/// disclosure; this is the permission. Shared by all three AI surfaces (Describe / Scan / Note analyze)
/// so the wording and behaviour are identical. Once accepted, `SettingsKeys.aiConsentGiven` is set and
/// the prompt never appears again.
extension View {
    func aiConsentGate(isPresented: Binding<Bool>, onAccept: @escaping () -> Void) -> some View {
        confirmationDialog("Use AI to read this?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Continue") { onAccept() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sends the text (or your photo's text) to our AI service (Anthropic) to extract "
                 + "medication details for you to review. Nothing is saved without your confirmation.")
        }
    }
}
