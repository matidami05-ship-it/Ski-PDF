import Foundation
import Vision
import PDFKit
import UIKit
import CoreText

/// On-device text recognition with Apple's Vision framework.
enum OCREngine {
    struct Line {
        let text: String
        /// Normalized box (0…1), origin bottom-left, as Vision reports it.
        let box: CGRect
    }

    static let languages: [(code: String, name: String)] = [
        ("en-US", "English"), ("pl-PL", "Polish"), ("es-ES", "Spanish"), ("fr-FR", "French"),
        ("de-DE", "German"), ("it-IT", "Italian"), ("pt-BR", "Portuguese"), ("uk-UA", "Ukrainian"),
        ("ru-RU", "Russian"), ("zh-Hans", "Chinese (Simplified)"), ("ja-JP", "Japanese"), ("ko-KR", "Korean"),
    ]

    static func recognize(_ image: CGImage, languages: [String]) throws -> [Line] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        if languages.isEmpty {
            req.automaticallyDetectsLanguage = true
        } else {
            req.recognitionLanguages = languages
        }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([req])
        let obs = req.results ?? []
        return obs.compactMap { o in
            guard let t = o.topCandidates(1).first?.string, !t.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return Line(text: t, box: o.boundingBox)
        }
    }

    /// Plain text from recognized lines, top to bottom.
    static func text(_ lines: [Line]) -> String {
        lines.sorted { a, b in
            if abs(a.box.midY - b.box.midY) > min(a.box.height, b.box.height) * 0.5 { return a.box.midY > b.box.midY }
            return a.box.minX < b.box.minX
        }.map(\.text).joined(separator: "\n")
    }

    /// Draws recognized text invisibly over a page so it can be searched, selected and copied.
    /// The context must be in UIKit coordinates (origin top-left) for a page of `size`.
    static func drawInvisibleText(_ lines: [Line], size: CGSize, cg: CGContext) {
        cg.saveGState()
        // Switch to PDF-style coordinates (origin bottom-left) to match Vision's boxes.
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        cg.setTextDrawingMode(.invisible)
        for line in lines {
            let r = CGRect(x: line.box.minX * size.width, y: line.box.minY * size.height,
                           width: line.box.width * size.width, height: line.box.height * size.height)
            guard r.width > 1, r.height > 1 else { continue }
            let fontSize = r.height * 0.82
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attr = NSAttributedString(string: line.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let ctLine = CTLineCreateWithAttributedString(attr)
            let width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
            guard width > 0 else { continue }
            cg.saveGState()
            cg.textMatrix = .identity
            cg.translateBy(x: r.minX, y: r.minY + r.height * 0.2)
            cg.scaleBy(x: r.width / CGFloat(width), y: 1)
            cg.textPosition = .zero
            CTLineDraw(ctLine, cg)
            cg.restoreGState()
        }
        cg.restoreGState()
    }

    /// Makes a searchable PDF: each page keeps its look, with an invisible text layer added.
    /// Returns the PDF data and all the recognized text.
    static func searchable(_ doc: PDFDocument, languages: [String], progress: ((Double) -> Void)?) throws -> (Data, String) {
        var allText: [String] = []
        var linesByPage: [Int: [Line]] = [:]
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            try autoreleasepool {
                let img = PDFEngine.image(of: page, dpi: 220, maxPixels: 3200)
                guard let cg = img.cgImage else { return }
                let lines = try recognize(cg, languages: languages)
                linesByPage[i] = lines
                allText.append("— Page \(i + 1) —\n" + text(lines))
            }
            progress?(Double(i + 1) / Double(max(1, doc.pageCount)) * 0.85)
        }
        let data = PDFEngine.redraw(doc, progress: { p in progress?(0.85 + p * 0.15) }) { i, size, cg in
            if let lines = linesByPage[i] { drawInvisibleText(lines, size: size, cg: cg) }
        }
        return (data, allText.joined(separator: "\n\n"))
    }

    /// Searchable PDF straight from images (used by Scan to PDF and OCR on photos).
    static func searchablePDF(images: [UIImage], languages: [String], quality: CGFloat, progress: ((Double) -> Void)?) throws -> (Data, String) {
        let data = NSMutableData()
        var texts: [String] = []
        UIGraphicsBeginPDFContextToData(data, .zero, [kCGPDFContextCreator as String: "Ski PDF"])
        var failure: Error?
        for (i, raw) in images.enumerated() where failure == nil {
            do { try autoreleasepool {
                let img = ImageEngine.normalized(raw)
                // Page in points: image shown at 150 dpi.
                let pxW = img.size.width * img.scale, pxH = img.size.height * img.scale
                let size = CGSize(width: pxW * 72 / 150, height: pxH * 72 / 150)
                UIGraphicsBeginPDFPageWithInfo(CGRect(origin: .zero, size: size), nil)
                let jpeg = img.jpegData(compressionQuality: quality).flatMap(UIImage.init(data:)) ?? img
                jpeg.draw(in: CGRect(origin: .zero, size: size))
                if let cgImg = img.cgImage, let ctx = UIGraphicsGetCurrentContext() {
                    let lines = try recognize(cgImg, languages: languages)
                    drawInvisibleText(lines, size: size, cg: ctx)
                    texts.append("— Page \(i + 1) —\n" + text(lines))
                }
            } } catch { failure = error }
            progress?(Double(i + 1) / Double(max(1, images.count)))
        }
        UIGraphicsEndPDFContext()
        if let failure { throw failure }
        return (data as Data, texts.joined(separator: "\n\n"))
    }
}
