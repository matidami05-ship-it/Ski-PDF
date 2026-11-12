import Foundation
import UIKit
import WebKit
import PDFKit
import Compression

/// Turns web pages, HTML, Word/Office files, RTF and text into PDFs.
@MainActor
final class WebPDFConverter: NSObject, WKNavigationDelegate {
    enum Layout: String, CaseIterable, Identifiable {
        case a4 = "A4 pages", letter = "Letter pages", long = "One long page"
        var id: String { rawValue }
        var paper: CGSize? {
            switch self {
            case .a4: return CGSize(width: 595.28, height: 841.89)
            case .letter: return CGSize(width: 612, height: 792)
            case .long: return nil
            }
        }
    }

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?
    private var holder: UIView?

    /// Loads a web address (http/https) and returns the PDF.
    func convert(url: URL, layout: Layout, landscape: Bool = false) async throws -> Data {
        let web = makeWebView(width: pageWidth(layout, landscape))
        try await load { web.load(URLRequest(url: url, timeoutInterval: 40)) }
        try await settle(web)
        return try await render(web, layout: layout, landscape: landscape)
    }

    /// Loads HTML text.
    func convert(html: String, baseURL: URL?, layout: Layout, landscape: Bool = false) async throws -> Data {
        let web = makeWebView(width: pageWidth(layout, landscape))
        try await load { web.loadHTMLString(html, baseURL: baseURL) }
        try await settle(web)
        return try await render(web, layout: layout, landscape: landscape)
    }

    /// Loads a local file WebKit can display (HTML, Office, iWork, RTF, text…).
    func convert(file: URL, layout: Layout, landscape: Bool = false) async throws -> Data {
        let web = makeWebView(width: pageWidth(layout, landscape))
        try await load { web.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent()) }
        try await settle(web)
        return try await render(web, layout: layout, landscape: landscape)
    }

    private func pageWidth(_ layout: Layout, _ landscape: Bool) -> CGFloat {
        guard let p = layout.paper else { return 900 }
        return landscape ? p.height : p.width
    }

    private func makeWebView(width: CGFloat) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: max(width, 600), height: 1200), configuration: config)
        web.navigationDelegate = self
        web.isOpaque = false
        // WebKit only lays out pages that are in a window; keep it off-screen.
        if let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            let h = UIView(frame: CGRect(x: -20000, y: 0, width: web.frame.width, height: web.frame.height))
            h.isUserInteractionEnabled = false
            h.alpha = 0.01
            h.addSubview(web)
            window.addSubview(h)
            holder = h
        }
        webView = web
        return web
    }

    private func load(_ start: () -> Void) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            continuation = c
            start()
        }
    }

    /// Gives scripts, fonts and images a moment to finish after the page reports loaded.
    private func settle(_ web: WKWebView) async throws {
        try await Task.sleep(nanoseconds: 700_000_000)
        _ = try? await web.evaluateJavaScript("document.fonts ? document.fonts.ready.then(()=>1) : 1")
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    private func render(_ web: WKWebView, layout: Layout, landscape: Bool) async throws -> Data {
        defer { cleanup() }
        if let paper = layout.paper {
            let sheet = landscape ? CGSize(width: paper.height, height: paper.width) : paper
            let renderer = UIPrintPageRenderer()
            renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
            let margin: CGFloat = 36
            let paperRect = CGRect(origin: .zero, size: sheet)
            renderer.setValue(NSValue(cgRect: paperRect), forKey: "paperRect")
            renderer.setValue(NSValue(cgRect: paperRect.insetBy(dx: margin, dy: margin)), forKey: "printableRect")
            let data = NSMutableData()
            UIGraphicsBeginPDFContextToData(data, paperRect, [kCGPDFContextCreator as String: "Ski PDF"])
            renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
            let bounds = UIGraphicsGetPDFContextBounds()
            for i in 0..<renderer.numberOfPages {
                UIGraphicsBeginPDFPage()
                renderer.drawPage(at: i, in: bounds)
            }
            UIGraphicsEndPDFContext()
            if renderer.numberOfPages > 0, (data as Data).count > 800 { return data as Data }
            // Some content (e.g. Office previews) doesn't paginate: fall back to one long page.
        }
        let config = WKPDFConfiguration()
        return try await web.pdf(configuration: config)
    }

    private func cleanup() {
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        holder?.removeFromSuperview()
        webView = nil
        holder = nil
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.continuation?.resume()
            self.continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.fail(error) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.fail(error) }
    }

    private func fail(_ error: Error) {
        continuation?.resume(throwing: ToolError("Couldn't load it: \(error.localizedDescription)"))
        continuation = nil
        cleanup()
    }
}

/// Text documents (Word .docx, RTF, plain text) laid out as real paginated text with UIKit's print system.
@MainActor
enum TextPDFConverter {
    static func pdf(from text: NSAttributedString, paper: CGSize, margin: CGFloat = 54) -> Data {
        let formatter = UISimpleTextPrintFormatter(attributedText: text)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let paperRect = CGRect(origin: .zero, size: paper)
        renderer.setValue(NSValue(cgRect: paperRect), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: paperRect.insetBy(dx: margin, dy: margin)), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paperRect, [kCGPDFContextCreator as String: "Ski PDF"])
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        let bounds = UIGraphicsGetPDFContextBounds()
        for i in 0..<max(1, renderer.numberOfPages) {
            UIGraphicsBeginPDFPage()
            if i < renderer.numberOfPages { renderer.drawPage(at: i, in: bounds) }
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    static func attributed(fromFile url: URL) throws -> NSAttributedString {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "docx":
            return try DocxReader.read(url)
        case "rtf", "rtfd":
            return try NSAttributedString(url: url, options: [.documentType: ext == "rtf" ? NSAttributedString.DocumentType.rtf : .rtfd], documentAttributes: nil)
        case "txt", "text", "md", "csv", "log", "json", "xml":
            let s = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
            return NSAttributedString(string: s, attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.black])
        default:
            throw ToolError("Not a text document.")
        }
    }
}

/// A small Word (.docx) reader: paragraphs, headings, bold/italic/underline/strike, sizes, colours,
/// alignment, bullet and numbered lists, tables and pictures.
enum DocxReader {
    static func read(_ url: URL) throws -> NSAttributedString {
        let zip = try ZipReader(url: url)
        guard let xml = zip.data("word/document.xml") else { throw ToolError("This isn't a Word document.") }
        var rels: [String: String] = [:]
        if let r = zip.data("word/_rels/document.xml.rels") { rels = RelsParser.parse(r) }
        var styleNames: [String: String] = [:]
        if let s = zip.data("word/styles.xml") { styleNames = StylesParser.parse(s) }
        let p = DocumentParser(styleNames: styleNames) { rid in
            guard let target = rels[rid] else { return nil }
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "word/" + target
            return zip.data(path)
        }
        return p.run(xml)
    }

    private final class RelsParser: NSObject, XMLParserDelegate {
        var map: [String: String] = [:]
        static func parse(_ d: Data) -> [String: String] {
            let p = RelsParser()
            let x = XMLParser(data: d)
            x.delegate = p
            x.parse()
            return p.map
        }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if name.hasSuffix("Relationship"), let id = attributes["Id"], let t = attributes["Target"] { map[id] = t }
        }
    }

    private final class StylesParser: NSObject, XMLParserDelegate {
        var map: [String: String] = [:]
        var current: String?
        static func parse(_ d: Data) -> [String: String] {
            let p = StylesParser()
            let x = XMLParser(data: d)
            x.delegate = p
            x.parse()
            return p.map
        }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if name == "w:style" { current = attributes["w:styleId"] }
            if name == "w:name", let c = current, let v = attributes["w:val"] { map[c] = v }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "w:style" { current = nil }
        }
    }

    private final class DocumentParser: NSObject, XMLParserDelegate {
        let styleNames: [String: String]
        let image: (String) -> Data?
        let out = NSMutableAttributedString()

        // paragraph state
        var para = NSMutableAttributedString()
        var heading = 0
        var align: NSTextAlignment = .natural
        var listLevel: Int?
        var numbered = false
        var numberCounters: [Int: Int] = [:]
        // run state
        var bold = false, italic = false, underline = false, strike = false
        var size: CGFloat?
        var color: UIColor?
        var inText = false
        var inRunProps = false
        var inParaProps = false
        // tables
        var tableDepth = 0
        var cellParas: [NSAttributedString] = []
        var rowCells: [NSAttributedString] = []
        var inCell = false
        var pendingImage: String?

        init(styleNames: [String: String], image: @escaping (String) -> Data?) {
            self.styleNames = styleNames
            self.image = image
        }

        func run(_ data: Data) -> NSAttributedString {
            let x = XMLParser(data: data)
            x.delegate = self
            x.parse()
            return out
        }

        var baseSize: CGFloat { 11 }

        func headingLevel(_ styleId: String) -> Int {
            let n = (styleNames[styleId] ?? styleId).lowercased().replacingOccurrences(of: " ", with: "")
            if n == "title" { return -1 }
            if n.hasPrefix("heading"), let l = Int(n.dropFirst(7)) { return max(1, min(4, l)) }
            if n == "subtitle" { return 3 }
            return 0
        }

        func headingSize(_ h: Int) -> CGFloat {
            switch h {
            case -1: return 26
            case 1: return 20
            case 2: return 16
            case 3: return 13.5
            case 4: return 12
            default: return baseSize
            }
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            switch name {
            case "w:p":
                para = NSMutableAttributedString()
                heading = 0; align = .natural; listLevel = nil; numbered = false
            case "w:pPr": inParaProps = true
            case "w:pStyle":
                if inParaProps, let v = a["w:val"] {
                    heading = headingLevel(v)
                    let lower = (styleNames[v] ?? v).lowercased()
                    if lower.contains("list number") { listLevel = 0; numbered = true }
                    else if lower.contains("list") && listLevel == nil { listLevel = 0 }
                }
            case "w:ilvl": if inParaProps { listLevel = Int(a["w:val"] ?? "0") ?? 0 }
            case "w:numId":
                if inParaProps {
                    if listLevel == nil { listLevel = 0 }
                    // numId values are opaque without numbering.xml; even ids are often numbered lists.
                    if a["w:val"] == "0" { listLevel = nil }
                }
            case "w:jc":
                if inParaProps {
                    switch a["w:val"] {
                    case "center": align = .center
                    case "right", "end": align = .right
                    case "both", "distribute": align = .justified
                    default: align = .natural
                    }
                }
            case "w:r":
                bold = heading != 0; italic = false; underline = false; strike = false; size = nil; color = nil
            case "w:rPr": inRunProps = true
            case "w:b": if inRunProps && !inParaProps { bold = a["w:val"].map { $0 != "0" && $0 != "false" } ?? true }
            case "w:i": if inRunProps && !inParaProps { italic = a["w:val"].map { $0 != "0" && $0 != "false" } ?? true }
            case "w:u": if inRunProps && !inParaProps { underline = (a["w:val"] ?? "single") != "none" }
            case "w:strike", "w:dstrike": if inRunProps && !inParaProps { strike = a["w:val"].map { $0 != "0" && $0 != "false" } ?? true }
            case "w:sz": if inRunProps && !inParaProps, let v = a["w:val"].flatMap(Double.init) { size = CGFloat(v / 2) }
            case "w:color":
                if inRunProps && !inParaProps, let hex = a["w:val"], hex.count == 6, hex != "auto", let n = UInt32(hex, radix: 16), n != 0 {
                    color = UIColor(red: CGFloat((n >> 16) & 0xFF) / 255, green: CGFloat((n >> 8) & 0xFF) / 255, blue: CGFloat(n & 0xFF) / 255, alpha: 1)
                }
            case "w:t": inText = true
            case "w:tab": append("\t")
            case "w:br":
                if a["w:type"] == "page" { append("\n") } else { append("\u{2028}") }
            case "w:cr": append("\u{2028}")
            case "a:blip":
                if let rid = a["r:embed"] { pendingImage = rid }
            case "w:tbl": tableDepth += 1
            case "w:tr": rowCells = []
            case "w:tc": inCell = true; cellParas = []
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { append(string) }
        }

        func append(_ s: String) {
            let fontSize = size ?? (heading != 0 ? headingSize(heading) : baseSize)
            var traits: UIFontDescriptor.SymbolicTraits = []
            if bold { traits.insert(.traitBold) }
            if italic { traits.insert(.traitItalic) }
            var font = UIFont.systemFont(ofSize: fontSize)
            if let d = font.fontDescriptor.withSymbolicTraits(traits) { font = UIFont(descriptor: d, size: fontSize) }
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color ?? UIColor.black]
            if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            para.append(NSAttributedString(string: s, attributes: attrs))
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "w:t": inText = false
            case "w:pPr": inParaProps = false
            case "w:rPr": inRunProps = false
            case "w:drawing", "w:pict":
                if let rid = pendingImage, let data = image(rid), let img = UIImage(data: data) {
                    let att = NSTextAttachment()
                    att.image = img
                    let maxW: CGFloat = 460
                    let w = min(maxW, img.size.width), h = img.size.height * w / max(1, img.size.width)
                    att.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                    para.append(NSAttributedString(attachment: att))
                }
                pendingImage = nil
            case "w:p":
                finishParagraph()
            case "w:tc":
                let cell = NSMutableAttributedString()
                for (i, p) in cellParas.enumerated() {
                    if i > 0 { cell.append(NSAttributedString(string: " ")) }
                    cell.append(p)
                }
                rowCells.append(cell)
                inCell = false
            case "w:tr":
                let row = NSMutableAttributedString()
                for (i, c) in rowCells.enumerated() {
                    if i > 0 { row.append(NSAttributedString(string: "  |  ", attributes: [.font: UIFont.systemFont(ofSize: baseSize), .foregroundColor: UIColor.gray])) }
                    row.append(c)
                }
                emit(row, style: paragraphStyle(spacing: 4))
            case "w:tbl":
                tableDepth -= 1
                emit(NSAttributedString(string: ""), style: paragraphStyle(spacing: 6))
            default: break
            }
        }

        func paragraphStyle(spacing: CGFloat) -> NSParagraphStyle {
            let ps = NSMutableParagraphStyle()
            ps.alignment = align
            ps.paragraphSpacing = spacing
            ps.lineHeightMultiple = 1.1
            return ps
        }

        func finishParagraph() {
            let content = NSMutableAttributedString(attributedString: para)
            if inCell {
                cellParas.append(content)
                return
            }
            let ps = NSMutableParagraphStyle()
            ps.alignment = align
            ps.lineHeightMultiple = 1.12
            ps.paragraphSpacing = heading != 0 ? 8 : 6
            ps.paragraphSpacingBefore = heading != 0 ? 10 : 0
            if let lvl = listLevel {
                let indent = CGFloat(18 + lvl * 18)
                ps.headIndent = indent
                ps.firstLineHeadIndent = indent - 14
                ps.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
                let marker: String
                if numbered {
                    let n = (numberCounters[lvl] ?? 0) + 1
                    numberCounters[lvl] = n
                    marker = "\(n).\t"
                } else {
                    marker = (lvl % 2 == 0 ? "•" : "◦") + "\t"
                }
                let font = (content.length > 0 ? content.attribute(.font, at: 0, effectiveRange: nil) as? UIFont : nil) ?? UIFont.systemFont(ofSize: baseSize)
                content.insert(NSAttributedString(string: marker, attributes: [.font: font, .foregroundColor: UIColor.black]), at: 0)
            } else {
                numberCounters.removeAll()
            }
            emit(content, style: ps)
        }

        func emit(_ s: NSAttributedString, style: NSParagraphStyle) {
            let m = NSMutableAttributedString(attributedString: s)
            m.append(NSAttributedString(string: "\n", attributes: [.font: UIFont.systemFont(ofSize: baseSize)]))
            m.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: m.length))
            out.append(m)
        }
    }
}

/// Minimal ZIP reader (stored and deflated entries) for Office files.
struct ZipReader {
    private var entries: [String: (offset: Int, method: UInt16, compSize: Int, size: Int)] = [:]
    private let data: Data

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .mappedIfSafe)
        // Find the end-of-central-directory record.
        let bytes = [UInt8](data.suffix(min(data.count, 66_000)))
        let base = data.count - bytes.count
        var eocd = -1
        var i = bytes.count - 22
        while i >= 0 {
            if bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06 { eocd = base + i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ToolError("This file is damaged or isn't an Office document.") }
        let count = Int(u16(eocd + 10))
        var p = Int(u32(eocd + 16))
        for _ in 0..<count {
            guard p + 46 <= data.count, u32(p) == 0x02014B50 else { break }
            let method = u16(p + 10)
            let comp = Int(u32(p + 20)), size = Int(u32(p + 24))
            let nameLen = Int(u16(p + 28)), extraLen = Int(u16(p + 30)), commentLen = Int(u16(p + 32))
            let local = Int(u32(p + 42))
            let nameData = data.subdata(in: (data.startIndex + p + 46)..<(data.startIndex + p + 46 + nameLen))
            let name = String(decoding: nameData, as: UTF8.self)
            entries[name] = (local, method, comp, size)
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    private func u16(_ o: Int) -> UInt16 {
        let s = data.startIndex + o
        return UInt16(data[s]) | UInt16(data[s + 1]) << 8
    }

    private func u32(_ o: Int) -> UInt32 {
        let s = data.startIndex + o
        return UInt32(data[s]) | UInt32(data[s + 1]) << 8 | UInt32(data[s + 2]) << 16 | UInt32(data[s + 3]) << 24
    }

    func data(_ name: String) -> Data? {
        guard let e = entries[name], e.offset + 30 <= data.count, u32(e.offset) == 0x04034B50 else { return nil }
        let start = e.offset + 30 + Int(u16(e.offset + 26)) + Int(u16(e.offset + 28))
        guard start + e.compSize <= data.count else { return nil }
        let comp = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + e.compSize))
        switch e.method {
        case 0: return comp
        case 8: return Inflate.raw(comp, expected: e.size)
        default: return nil
        }
    }
}

enum Inflate {
    /// Decompresses raw DEFLATE data (what ZIP files use).
    static func raw(_ input: Data, expected: Int) -> Data? {
        let cap = max(expected, 64)
        var out = Data(count: cap)
        let n = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, cap,
                                          src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 || expected == 0 else { return nil }
        out.count = n
        return out
    }
}
