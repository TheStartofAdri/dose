import SwiftUI
import UIKit

/// Thin wrapper over `UIActivityViewController` — the iOS share sheet. The user picks the destination
/// (Messages / Mail / Files / AirDrop); the app sends nothing itself, so medication data leaves the
/// device only on this explicit action.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Identifiable wrapper so a generated PDF URL can drive `.sheet(item:)`.
struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}
