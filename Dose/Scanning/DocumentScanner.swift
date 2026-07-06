import SwiftUI
import VisionKit

/// Thin SwiftUI wrapper around `VNDocumentCameraViewController`. This is the only scan piece that
/// needs real camera hardware — it emits a `CGImage` and hands off to `LabelTextRecognizer`, which
/// is fully testable in the Simulator without it.
struct DocumentScanner: UIViewControllerRepresentable {
    var onScan: (CGImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0, let cgImage = scan.imageOfPage(at: 0).cgImage else {
                parent.onCancel()
                return
            }
            parent.onScan(cgImage)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}
