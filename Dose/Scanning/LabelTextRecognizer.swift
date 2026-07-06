import Foundation
import Vision
import CoreGraphics

/// Raw OCR output. No interpretation happens here — structuring is the AI layer's job.
struct OCRResult: Equatable {
    let text: String
    let lines: [String]
}

enum OCRError: Error {
    case noText
}

/// Recognizes text from a still image. Deliberately decoupled from any capture session — it takes
/// a `CGImage`, so it runs in the Simulator and in unit tests against a bundled label image. The
/// camera capture step (`DocumentScanner`) is the only piece that needs real hardware.
///
/// Recognizes **English + Russian in one pass** (no manual pre-selection): `["ru-RU","en-US"]` with
/// `usesLanguageCorrection = false`. Correction stays OFF because, with two languages active, the
/// model is more likely to "correct" a real drug name into a wrong dictionary word. The known
/// tradeoff — dual-language recognition can occasionally misread a word across languages — is
/// acceptable because the review screen catches it before saving. (Vision has no Kazakh recognizer.)
enum LabelTextRecognizer {
    static let defaultLanguages = ["ru-RU", "en-US"]

    static func recognize(
        in cgImage: CGImage,
        languages: [String] = LabelTextRecognizer.defaultLanguages
    ) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate          // required for Cyrillic; .fast is Latin-only
        request.usesLanguageCorrection = false
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { throw OCRError.noText }
        return OCRResult(text: lines.joined(separator: "\n"), lines: lines)
    }
}
