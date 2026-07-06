import XCTest
import UIKit
@testable import Dose

/// Verifies the OCR seam runs in the Simulator (no camera) and **measures** whether Kazakh-specific
/// glyphs survive recognition — the make-or-break question for the KK wedge. KK survival is an
/// empirical launch gate, so it is surfaced (printed/attached), not asserted away.
final class LabelRecognizerTests: XCTestCase {

    private func render(_ text: String, size: CGSize = CGSize(width: 1100, height: 420)) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 10
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 60, weight: .semibold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: style,
            ]
            (text as NSString).draw(in: CGRect(x: 30, y: 30, width: size.width - 60, height: size.height - 60),
                                    withAttributes: attrs)
        }
        return image.cgImage!
    }

    func testRecognizesLatinText() throws {
        let result = try LabelTextRecognizer.recognize(in: render("Paracetamol 500 mg"), languages: ["en-US"])
        XCTAssertTrue(result.text.lowercased().contains("paracetamol"),
                      "Latin OCR should recognize the drug name. Got: \(result.text)")
    }

    func testRecognizesRussianCyrillicWithDefaultLanguages() throws {
        // Default is now dual-language ["ru-RU","en-US"] — no manual pre-selection needed.
        let result = try LabelTextRecognizer.recognize(in: render("Парацетамол 500 мг"))
        XCTAssertTrue(result.text.lowercased().contains("парацетамол"),
                      "Dual-language OCR should read Russian Cyrillic. Got: \(result.text)")
    }

    func testDefaultLanguagesAreRussianAndEnglish() {
        XCTAssertEqual(LabelTextRecognizer.defaultLanguages, ["ru-RU", "en-US"])
    }

    func testKazakhGlyphSurvivalIsMeasured() throws {
        // The eight Kazakh-specific letters that Russian doesn't have.
        let special = "әғқңөұүі"
        let sentence = "Дәрі қабылдау: күніне үш рет"   // realistic Kazakh, contains several specials
        let result = try LabelTextRecognizer.recognize(in: render(sentence + "  " + special))

        // The pipeline itself must run in the Simulator and return text (the seam works headless).
        XCTAssertFalse(result.text.isEmpty, "OCR should return text in the Simulator")

        let survived = special.filter { result.text.contains($0) }
        let missing = special.filter { !result.text.contains($0) }
        let report = "Kazakh glyph survival — survived [\(String(survived))], missing [\(String(missing))]\nraw OCR: \(result.text)"
        print(report)
        add(XCTAttachment(string: report))

        // Documentary, not a pass/fail gate: KK survival is validated against real packaging before
        // marketing the KK wedge (see the plan). The assertion above guards the seam; this records
        // the empirical finding so it is surfaced, not buried.
    }
}
