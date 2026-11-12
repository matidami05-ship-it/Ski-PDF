import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

/// All the PDF work Ski PDF does, built on PDFKit and Core Graphics. Everything here runs off the main thread.
enum PDFEngine {

    // MARK: Saving

    /// Writes a document into the library under the given name.
    static func save(_ doc: PDFDocument, name: String, options: [PDFDocumentWriteOption: Any] = [:]) throws -> LibraryFile {
        let tmp = Scratch.url(ensurePDF(name))
        let ok = options.isEmpty ? doc.write(to: tmp) : doc.write(to: tmp, withOptions: options)
        guard ok else { throw ToolError("Couldn't write the PDF.") }
        return try FileLibrary.shared.adopt(tmp, name: ensurePDF(name))
    }

    static func save(_ data: Data, name: String) throws -> LibraryFile {
        try FileLibrary.shared.save(data, name: ensurePDF(name))
    }

    static func ensurePDF(_ name: String) -> String {
        name.lowercased().hasSuffix(".pdf") ? name : name + ".pdf"
    }

    // MARK: Page operations

    /// A new document holding copies of the given pages (0-based), in that order.
    static func subset(_ doc: PDFDocument, pages: [Int]) -> PDFDocument {
        let out = PDFDocument()
        for (i, idx) in pages.enumerated() {
            guard let p = doc.page(at: idx)?.copy() as? PDFPage else { continue }
            out.insert(p, at: i)
        }
        copyAttributes(from: doc, to: out)
        return out
    }

    static func merge(_ docs: [PDFDocument]) -> PDFDocument {
        let out = PDFDocument()
        var n = 0
        for d in docs {
            for i in 0..<d.pageCount {
                guard let p = d.page(at: i)?.copy() as? PDFPage else { continue }
                out.insert(p, at: n)
                n += 1
            }
        }
        return out
    }

    /// Rotations per page in degrees (multiples of 90), applied on top of each page's current rotation.
    static func rotated(_ doc: PDFDocument, by degrees: [Int: Int]) -> PDFDocument {
        let out = subset(doc, pages: Array(0..<doc.pageCount))
        for (i, d) in degrees where d % 360 != 0 {
            guard let p = out.page(at: i) else { continue }
            p.rotation = ((p.rotation + d) % 360 + 360) % 360
        }
        return out
    }

    static func copyAttributes(from: PDFDocument, to: PDFDocument) {
        if let a = from.documentAttributes { to.documentAttributes = a }
    }

    // MARK: Redrawing (watermarks, page numbers, signatures, flattening, n-up)

    /// Size of a page as it is shown (rotation applied), in points.
    static func displaySize(_ page: PDFPage) -> CGSize {
        let b = page.bounds(for: .cropBox)
        return (page.rotation % 180 == 0) ? b.size : CGSize(width: b.height, height: b.width)
    }

    /// Draws a page (with its annotations and form fields) into a UIKit-style context whose origin is the
    /// top-left of `rect`, scaled to fill `rect`.
    static func drawPage(_ page: PDFPage, in rect: CGRect, context cg: CGContext) {
        let size = displaySize(page)
        guard size.width > 0, size.height > 0 else { return }
        cg.saveGState()
        cg.translateBy(x: rect.minX, y: rect.maxY)
        cg.scaleBy(x: rect.width / size.width, y: -rect.height / size.height)
        // PDFKit applies the page's rotation and crop-box origin itself.
        page.draw(with: .cropBox, to: cg)
        cg.restoreGState()
    }

    /// Re-creates a document page by page. `overlay` draws on top of each page in UIKit coordinates
    /// (origin top-left, size = displayed page size). The result has no form fields or annotations:
    /// everything becomes part of the page.
    static func redraw(_ doc: PDFDocument,
                       pages: [Int]? = nil,
                       progress: ((Double) -> Void)? = nil,
                       overlay: ((Int, CGSize, CGContext) -> Void)? = nil) -> Data {
        let indexes = pages ?? Array(0..<doc.pageCount)
        let data = NSMutableData()
        let first = indexes.first.flatMap { doc.page(at: $0) }.map(displaySize) ?? CGSize(width: 612, height: 792)
        UIGraphicsBeginPDFContextToData(data, CGRect(origin: .zero, size: first), pdfInfo(doc))
        for (n, i) in indexes.enumerated() {
            guard let page = doc.page(at: i) else { continue }
            let size = displaySize(page)
            UIGraphicsBeginPDFPageWithInfo(CGRect(origin: .zero, size: size), nil)
            guard let cg = UIGraphicsGetCurrentContext() else { continue }
            autoreleasepool {
                drawPage(page, in: CGRect(origin: .zero, size: size), context: cg)
                if let overlay {
                    cg.saveGState()
                    overlay(i, size, cg)
                    cg.restoreGState()
                }
            }
            progress?(Double(n + 1) / Double(max(1, indexes.count)))
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    /// Document info (title, author, …) for a Core Graphics PDF context.
    static func pdfInfo(_ doc: PDFDocument) -> [String: Any] {
        var info: [String: Any] = [kCGPDFContextCreator as String: "Ski PDF"]
        let a = doc.documentAttributes ?? [:]
        if let t = a[PDFDocumentAttribute.titleAttribute] as? String { info[kCGPDFContextTitle as String] = t }
        if let t = a[PDFDocumentAttribute.authorAttribute] as? String { info[kCGPDFContextAuthor as String] = t }
        if let t = a[PDFDocumentAttribute.subjectAttribute] as? String { info[kCGPDFContextSubject as String] = t }
        if let k = a[PDFDocumentAttribute.keywordsAttribute] { info[kCGPDFContextKeywords as String] = k }
        return info
    }

    // MARK: Rasterizing

    /// A page as a bitmap at the given resolution (72 dpi = 1 point per pixel). White background.
    static func image(of page: PDFPage, dpi: CGFloat, maxPixels: CGFloat = 6000) -> UIImage {
        let size = displaySize(page)
        var scale = dpi / 72
        let longest = max(size.width, size.height) * scale
        if longest > maxPixels { scale *= maxPixels / longest }
        let px = CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: px, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: px))
            drawPage(page, in: CGRect(origin: .zero, size: px), context: ctx.cgContext)
        }
    }

    /// Rebuilds the document from page images: smallest files, but text is no longer selectable.
    static func rasterized(_ doc: PDFDocument, dpi: CGFloat, quality: CGFloat, grayscale: Bool, progress: ((Double) -> Void)?) -> Data {
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, .zero, pdfInfo(doc))
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            autoreleasepool {
                let size = displaySize(page)
                var img = image(of: page, dpi: dpi)
                if grayscale, let g = ImageEngine.grayscale(img) { img = g }
                // Re-decode from JPEG so the PDF stores compact JPEG data.
                if let jpg = img.jpegData(compressionQuality: quality), let j = UIImage(data: jpg) { img = j }
                UIGraphicsBeginPDFPageWithInfo(CGRect(origin: .zero, size: size), nil)
                img.draw(in: CGRect(origin: .zero, size: size))
            }
            progress?(Double(i + 1) / Double(max(1, doc.pageCount)))
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    // MARK: Compress

    enum CompressLevel: String, CaseIterable, Identifiable {
        case light = "Light", medium = "Medium", strong = "Strong"
        var id: String { rawValue }
        var detail: String {
            switch self {
            case .light: return "Keeps text sharp and selectable. Shrinks pictures inside the PDF."
            case .medium: return "Pages become 150 dpi images. Much smaller; text can't be selected."
            case .strong: return "Pages become 96 dpi images. Smallest; fine for reading on screen."
            }
        }
    }

    static func compress(_ doc: PDFDocument, level: CompressLevel, grayscale: Bool, progress: ((Double) -> Void)?) throws -> Data {
        switch level {
        case .light:
            let tmp = Scratch.url("light.pdf")
            let opts: [PDFDocumentWriteOption: Any] = [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]
            if grayscale {
                return rasterized(doc, dpi: 200, quality: 0.75, grayscale: true, progress: progress)
            }
            guard doc.write(to: tmp, withOptions: opts) else { throw ToolError("Couldn't compress this PDF.") }
            progress?(1)
            return try Data(contentsOf: tmp)
        case .medium:
            return rasterized(doc, dpi: 150, quality: 0.6, grayscale: grayscale, progress: progress)
        case .strong:
            return rasterized(doc, dpi: 96, quality: 0.45, grayscale: grayscale, progress: progress)
        }
    }

    // MARK: Security

    static func locked(_ doc: PDFDocument, userPassword: String, ownerPassword: String?, allowPrinting: Bool, allowCopying: Bool) throws -> URL {
        let tmp = Scratch.url("locked.pdf")
        var opts: [PDFDocumentWriteOption: Any] = [.userPasswordOption: userPassword,
                                                   .ownerPasswordOption: (ownerPassword?.isEmpty == false ? ownerPassword! : userPassword)]
        var perms: PDFAccessPermissions = [.allowsContentAccessibility]
        if allowPrinting { perms.insert(.allowsLowQualityPrinting); perms.insert(.allowsHighQualityPrinting) }
        if allowCopying { perms.insert(.allowsContentCopying) }
        opts[.accessPermissionsOption] = perms.rawValue
        guard doc.write(to: tmp, withOptions: opts) else { throw ToolError("Couldn't lock this PDF.") }
        return tmp
    }

    /// A copy without any password (the document must already be unlocked).
    static func unlocked(_ doc: PDFDocument) throws -> PDFDocument {
        guard !doc.isLocked else { throw ToolError("Enter the PDF's password first.") }
        let out = subset(doc, pages: Array(0..<doc.pageCount))
        // Re-read through data so no encryption carries over.
        if let data = out.dataRepresentation(), let fresh = PDFDocument(data: data), !fresh.isEncrypted {
            return fresh
        }
        let redrawn = redraw(doc)
        guard let r = PDFDocument(data: redrawn) else { throw ToolError("Couldn't remove the password.") }
        return r
    }

    // MARK: Text

    static func text(of doc: PDFDocument) -> String {
        var parts: [String] = []
        for i in 0..<doc.pageCount {
            parts.append(doc.page(at: i)?.string ?? "")
        }
        return parts.enumerated().map { "— Page \($0.offset + 1) —\n\($0.element.trimmingCharacters(in: .whitespacesAndNewlines))" }.joined(separator: "\n\n")
    }

    /// True if pages have hardly any real text (likely a scan).
    static func looksScanned(_ doc: PDFDocument) -> Bool {
        let sample = min(doc.pageCount, 5)
        guard sample > 0 else { return false }
        var chars = 0
        for i in 0..<sample { chars += doc.page(at: i)?.string?.count ?? 0 }
        return chars < 40 * sample
    }

    // MARK: Images → PDF

    enum PageSize: String, CaseIterable, Identifiable {
        case fit = "Fit image", a4 = "A4", letter = "Letter"
        var id: String { rawValue }
        var size: CGSize? {
            switch self {
            case .fit: return nil
            case .a4: return CGSize(width: 595.28, height: 841.89)
            case .letter: return CGSize(width: 612, height: 792)
            }
        }
    }

    static func pdf(from images: [UIImage], pageSize: PageSize, margin: CGFloat, quality: CGFloat, progress: ((Double) -> Void)?) -> Data {
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, .zero, [kCGPDFContextCreator as String: "Ski PDF"])
        for (i, raw) in images.enumerated() {
            autoreleasepool {
                let img = ImageEngine.normalized(raw)
                let jpeg = img.jpegData(compressionQuality: quality).flatMap(UIImage.init(data:)) ?? img
                // Points: image pixels shown at 150 dpi so phone photos make sensible page sizes.
                let natural = CGSize(width: img.size.width * img.scale * 72 / 150, height: img.size.height * img.scale * 72 / 150)
                var page: CGSize
                if let s = pageSize.size {
                    page = s
                    if natural.width > natural.height { page = CGSize(width: s.height, height: s.width) } // landscape photo → landscape page
                } else {
                    page = CGSize(width: natural.width + margin * 2, height: natural.height + margin * 2)
                }
                UIGraphicsBeginPDFPageWithInfo(CGRect(origin: .zero, size: page), nil)
                let box = CGRect(origin: .zero, size: page).insetBy(dx: margin, dy: margin)
                jpeg.draw(in: aspectFit(img.size, in: box))
            }
            progress?(Double(i + 1) / Double(max(1, images.count)))
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    static func aspectFit(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return box }
        let s = min(box.width / size.width, box.height / size.height)
        let w = size.width * s, h = size.height * s
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }

    // MARK: N-up (pages per sheet) for printing

    static func nUp(_ doc: PDFDocument, pages: [Int], perSheet: Int, sheet: CGSize, borders: Bool) -> Data {
        let (cols, rows): (Int, Int) = {
            switch perSheet {
            case 2: return (1, 2)
            case 4: return (2, 2)
            case 6: return (2, 3)
            case 9: return (3, 3)
            default: return (1, 1)
            }
        }()
        // Two per sheet reads best side by side on a landscape sheet.
        var sheetSize = sheet
        var c = cols, r = rows
        if perSheet == 2 { sheetSize = CGSize(width: sheet.height, height: sheet.width); c = 2; r = 1 }
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, CGRect(origin: .zero, size: sheetSize), pdfInfo(doc))
        let margin: CGFloat = 18, gap: CGFloat = 10
        let cellW = (sheetSize.width - margin * 2 - gap * CGFloat(c - 1)) / CGFloat(c)
        let cellH = (sheetSize.height - margin * 2 - gap * CGFloat(r - 1)) / CGFloat(r)
        var idx = 0
        while idx < pages.count {
            UIGraphicsBeginPDFPageWithInfo(CGRect(origin: .zero, size: sheetSize), nil)
            guard let cg = UIGraphicsGetCurrentContext() else { break }
            for slot in 0..<(c * r) where idx < pages.count {
                guard let page = doc.page(at: pages[idx]) else { idx += 1; continue }
                let col = slot % c, row = slot / c
                let cell = CGRect(x: margin + CGFloat(col) * (cellW + gap), y: margin + CGFloat(row) * (cellH + gap), width: cellW, height: cellH)
                let rect = aspectFit(displaySize(page), in: cell)
                drawPage(page, in: rect, context: cg)
                if borders {
                    cg.setStrokeColor(UIColor.gray.cgColor)
                    cg.setLineWidth(0.5)
                    cg.stroke(rect)
                }
                idx += 1
            }
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    // MARK: Overlays

    struct WatermarkStyle {
        var text: String
        var fontSize: CGFloat
        var color: UIColor
        var opacity: CGFloat
        var angle: CGFloat        // degrees
        var tiled: Bool
        var bold: Bool
    }

    static func drawWatermark(_ s: WatermarkStyle, size: CGSize, cg: CGContext) {
        let font = s.bold ? UIFont.systemFont(ofSize: s.fontSize, weight: .heavy) : UIFont.systemFont(ofSize: s.fontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: s.color.withAlphaComponent(s.opacity)]
        let str = NSAttributedString(string: s.text, attributes: attrs)
        let ts = str.size()
        UIGraphicsPushContext(cg)
        defer { UIGraphicsPopContext() }
        let rad = s.angle * .pi / 180
        if s.tiled {
            let stepX = ts.width + s.fontSize * 2.5
            let stepY = ts.height + s.fontSize * 3
            let diag = hypot(size.width, size.height)
            cg.saveGState()
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: -rad)
            var y = -diag / 2
            var row = 0
            while y < diag / 2 {
                var x = -diag / 2 + (row % 2 == 0 ? 0 : stepX / 2)
                while x < diag / 2 {
                    str.draw(at: CGPoint(x: x, y: y))
                    x += stepX
                }
                y += stepY
                row += 1
            }
            cg.restoreGState()
        } else {
            cg.saveGState()
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: -rad)
            str.draw(at: CGPoint(x: -ts.width / 2, y: -ts.height / 2))
            cg.restoreGState()
        }
    }

    enum NumberPosition: String, CaseIterable, Identifiable {
        case bottomCenter = "Bottom center", bottomRight = "Bottom right", bottomLeft = "Bottom left"
        case topCenter = "Top center", topRight = "Top right", topLeft = "Top left"
        var id: String { rawValue }
    }

    enum NumberFormat: String, CaseIterable, Identifiable {
        case plain = "1", page = "Page 1", ofTotal = "1 of 10", pageOfTotal = "Page 1 of 10", dashed = "- 1 -"
        var id: String { rawValue }
        func text(_ n: Int, total: Int) -> String {
            switch self {
            case .plain: return "\(n)"
            case .page: return "Page \(n)"
            case .ofTotal: return "\(n) of \(total)"
            case .pageOfTotal: return "Page \(n) of \(total)"
            case .dashed: return "- \(n) -"
            }
        }
    }

    static func drawPageNumber(_ text: String, position: NumberPosition, fontSize: CGFloat, color: UIColor, margin: CGFloat, size: CGSize, cg: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fontSize, weight: .medium), .foregroundColor: color]
        let s = NSAttributedString(string: text, attributes: attrs)
        let ts = s.size()
        let x: CGFloat
        switch position {
        case .bottomLeft, .topLeft: x = margin
        case .bottomRight, .topRight: x = size.width - margin - ts.width
        default: x = (size.width - ts.width) / 2
        }
        let y: CGFloat
        switch position {
        case .topLeft, .topCenter, .topRight: y = margin
        default: y = size.height - margin - ts.height
        }
        UIGraphicsPushContext(cg)
        s.draw(at: CGPoint(x: x, y: y))
        UIGraphicsPopContext()
    }
}
