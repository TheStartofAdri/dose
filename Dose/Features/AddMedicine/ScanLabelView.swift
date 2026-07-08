import SwiftUI
import UIKit

/// Scan label flow (premium). Camera capture → OCR (raw text only) → edge function → review gate.
/// Live `VNDocumentCameraViewController` capture needs real hardware; in the Simulator a DEBUG
/// "sample label" path feeds a rendered image through the same `LabelTextRecognizer`, so the whole
/// pipeline minus capture is exercisable without a device.
struct ScanLabelView: View {
    private let parser: MedicationParser = MedicationParserFactory.make()

    @State private var showScanner = false
    @State private var isReading = false
    @State private var errorMessage: String?
    @State private var drafts: [EditableDraft] = []
    @State private var goReview = false
    @AppStorage(SettingsKeys.aiConsentGiven) private var aiConsentGiven = false
    @State private var showAIConsent = false
    @State private var pendingScan: (() -> Void)?

    var body: some View {
        Group {
            if !AppConfig.aiConfigured {
                NotConfiguredView()
            } else if isReading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Reading label…").foregroundStyle(.secondary)
                }
            } else {
                idle
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner(
                onScan: { cgImage in showScanner = false; read(cgImage) },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .navigationDestination(isPresented: $goReview) {
            ReviewConfirmView(drafts: drafts, onRetake: { goReview = false; showScanner = true })
        }
        .aiConsentGate(isPresented: $showAIConsent) {
            aiConsentGiven = true
            let go = pendingScan; pendingScan = nil; go?()
        }
    }

    private var idle: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.pink)
            Text("Align the label inside the frame, hold steady, and capture.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }

            Button {
                requestScan { showScanner = true }
            } label: {
                Label("Scan with camera", systemImage: "camera")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            #if DEBUG
            Button("Use sample label (Simulator)") {
                requestScan { if let image = Self.sampleLabelImage() { read(image) } }
            }
            .font(.footnote)
            #endif
        }
        .padding()
    }

    /// First AI use shows the one-time consent (data leaves the device only at the parse step); after
    /// that the requested capture/read runs directly.
    private func requestScan(_ action: @escaping () -> Void) {
        errorMessage = nil
        if aiConsentGiven { action() } else { pendingScan = action; showAIConsent = true }
    }

    private func read(_ cgImage: CGImage) {
        isReading = true
        errorMessage = nil
        Task {
            do {
                // Vision's `.accurate` recognition is synchronous and slow (~0.5–3s). Run it OFF the
                // main actor so the "Reading label…" spinner keeps animating and the scanner-dismiss
                // animation doesn't hitch; state writes below stay on the main actor.
                let ocr = try await Task.detached(priority: .userInitiated) {
                    try LabelTextRecognizer.recognize(in: cgImage)
                }.value
                let parsed = try await parser.parse(.scan(ocrText: ocr.text))
                drafts = parsed.map { EditableDraft(from: $0, source: .scan) }
                isReading = false
                if drafts.isEmpty {
                    errorMessage = "Couldn't find a medicine on that label. Try again or add it manually."
                } else {
                    goReview = true
                }
            } catch {
                isReading = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    #if DEBUG
    /// Renders a synthetic multilingual label so the scan pipeline can be exercised in the Simulator.
    static func sampleLabelImage() -> CGImage? {
        let size = CGSize(width: 1000, height: 600)
        let text = """
        Paracetamol 500 mg
        Парацетамол, таблетки
        По 1 таблетке 2 раза в день
        Қабылдау: күніне 2 рет
        """
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 12
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 56, weight: .semibold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: style,
            ]
            (text as NSString).draw(in: CGRect(x: 40, y: 40, width: size.width - 80, height: size.height - 80),
                                    withAttributes: attrs)
        }
        return image.cgImage
    }
    #endif
}
