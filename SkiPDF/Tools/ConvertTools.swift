import SwiftUI
import PDFKit
import VisionKit
import UniformTypeIdentifiers

// MARK: - HTML / web page to PDF

struct HTMLToPDFTool: View {
    enum Source: String, CaseIterable, Identifiable {
        case web = "Web address", file = "HTML file", code = "Paste HTML"
        var id: String { rawValue }
    }

    @StateObject private var runner = ToolRunner()
    @State private var source = Source.web
    @State private var address = ""
    @State private var html = "<h1>Hello</h1>\n<p>Paste or type HTML here.</p>"
    @State private var file: URL?
    @State private var showImporter = false
    @State private var layout = WebPDFConverter.Layout.letter
    @State private var landscape = false
    @State private var name = ""

    private var ready: Bool {
        switch source {
        case .web: return normalizedURL != nil
        case .file: return file != nil
        case .code: return !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var normalizedURL: URL? {
        var s = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(" ") else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "https://" + s }
        guard let u = URL(string: s), u.host?.contains(".") == true else { return nil }
        return u
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Source", selection: $source) { ForEach(Source.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                switch source {
                case .web:
                    Panel(title: "Web address") {
                        TextField("example.com/article", text: $address)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if let clip = UIPasteboard.general.url, address.isEmpty {
                            Button("Paste \(clip.host ?? "link")") { address = clip.absoluteString }.font(.footnote)
                        }
                    }
                case .file:
                    Panel(title: "HTML file") {
                        if let f = file {
                            HStack {
                                Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(Theme.accent)
                                Text(f.lastPathComponent).lineLimit(1)
                                Spacer()
                                Button { file = nil } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(.secondary)
                            }
                        } else {
                            Button { showImporter = true } label: { Label("Choose HTML file", systemImage: "folder") }
                        }
                    }
                case .code:
                    Panel(title: "HTML") {
                        TextEditor(text: $html)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 180)
                            .scrollContentBackground(.hidden)
                            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Panel(title: "Layout") {
                    Picker("Pages", selection: $layout) { ForEach(WebPDFConverter.Layout.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented)
                    if layout != .long { Toggle("Landscape", isOn: $landscape) }
                }
                Panel(title: "File name") { TextField("Optional", text: $name).textFieldStyle(.roundedBorder) }
            }
            .padding(16)
        }
        .toolBackground()
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Convert to PDF", systemImage: "globe", busy: runner.busy, disabled: !ready, action: convert)
                .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.html, .webArchive, .xml, .plainText]) { r in
            if case .success(let u) = r { file = try? Scratch.copyIn(u) }
        }
        .toolRunner(runner)
    }

    private func convert() {
        runner.busy = true
        let lay = layout, land = landscape
        Task { @MainActor in
            do {
                let conv = WebPDFConverter()
                let data: Data
                var title = name
                switch source {
                case .web:
                    guard let u = normalizedURL else { return }
                    data = try await conv.convert(url: u, layout: lay, landscape: land)
                    if title.isEmpty { title = u.host ?? "Web page" }
                case .file:
                    guard let f = file else { return }
                    data = try await conv.convert(file: f, layout: lay, landscape: land)
                    if title.isEmpty { title = f.deletingPathExtension().lastPathComponent }
                case .code:
                    data = try await conv.convert(html: html, baseURL: nil, layout: lay, landscape: land)
                    if title.isEmpty { title = "HTML" }
                }
                let f = try PDFEngine.save(data, name: title)
                let pages = PDFDocument(data: data)?.pageCount ?? 0
                runner.busy = false
                runner.result = ToolResult(files: [f], message: "Saved as a \(pages)-page PDF.")
            } catch {
                runner.busy = false
                runner.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

// MARK: - Scan to PDF

struct ScanTool: View {
    enum Filter: String, CaseIterable, Identifiable {
        case color = "Color", enhanced = "Enhanced", gray = "Grayscale", bw = "Black & White"
        var id: String { rawValue }
        func apply(_ img: UIImage) -> UIImage {
            switch self {
            case .color: return img
            case .enhanced: return ImageEngine.enhanced(img) ?? img
            case .gray: return ImageEngine.grayscale(img) ?? img
            case .bw: return ImageEngine.blackAndWhite(img) ?? img
            }
        }
    }

    @StateObject private var runner = ToolRunner()
    @State private var pages: [UIImage] = []
    @State private var showScanner = false
    @State private var filter = Filter.enhanced
    @State private var ocr = true
    @State private var name = "Scan"

    var body: some View {
        List {
            Section {
                Button { showScanner = true } label: {
                    Label(pages.isEmpty ? "Start scanning" : "Scan more pages", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.iconTile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(!VNDocumentCameraViewController.isSupported)
                if !VNDocumentCameraViewController.isSupported {
                    Text("This device can't scan documents.").font(.footnote).foregroundStyle(.secondary)
                } else if pages.isEmpty {
                    Text("Hold your iPhone over the page. It finds the edges and straightens the page for you.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            if !pages.isEmpty {
                Section("\(pages.count) page\(pages.count == 1 ? "" : "s") — drag to reorder") {
                    ForEach(Array(pages.enumerated()), id: \.offset) { i, img in
                        HStack(spacing: 12) {
                            Image(uiImage: filter.apply(thumbnail(img))).resizable().scaledToFit().frame(width: 48, height: 64)
                            Text("Page \(i + 1)")
                        }
                    }
                    .onMove { pages.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { pages.remove(atOffsets: $0) }
                }
                Section("Look") {
                    Picker("Filter", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Make text searchable (OCR)", isOn: $ocr)
                }
                Section("File name") { TextField("Name", text: $name) }
            }
        }
        .environment(\.editMode, .constant(pages.count > 1 ? .active : .inactive))
        .scrollContentBackground(.hidden)
        .toolBackground()
        .safeAreaInset(edge: .bottom) {
            if !pages.isEmpty {
                PrimaryButton(title: "Save PDF", systemImage: "doc.viewfinder", busy: runner.busy) { save() }
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { scanned in pages += scanned }.ignoresSafeArea()
        }
        .toolRunner(runner)
    }

    private func thumbnail(_ img: UIImage) -> UIImage {
        let s = 160 / max(img.size.width, img.size.height)
        return UIGraphicsImageRenderer(size: CGSize(width: img.size.width * s, height: img.size.height * s)).image { _ in
            img.draw(in: CGRect(origin: .zero, size: CGSize(width: img.size.width * s, height: img.size.height * s)))
        }
    }

    private func save() {
        let imgs = pages, f = filter, doOCR = ocr, n = name
        runner.run { progress in
            let processed = imgs.map { f.apply($0) }
            if doOCR {
                let (data, _) = try OCREngine.searchablePDF(images: processed, languages: [], quality: 0.75, progress: progress)
                let file = try PDFEngine.save(data, name: n)
                return ToolResult(files: [file], message: "Scanned \(imgs.count) page(s). Text is searchable.")
            }
            let data = PDFEngine.pdf(from: processed, pageSize: .fit, margin: 0, quality: 0.75, progress: progress)
            let file = try PDFEngine.save(data, name: n)
            return ToolResult(files: [file], message: "Scanned \(imgs.count) page(s).")
        }
    }
}

struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    @Environment(\.dismiss) var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ p: DocumentScanner) { parent = p }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let imgs = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onScan(imgs)
            parent.dismiss()
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.dismiss() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.dismiss() }
    }
}

// MARK: - Doc to PDF

struct DocToPDFTool: View {
    @StateObject private var runner = ToolRunner()
    @State private var file: URL?
    @State private var showImporter = false
    @State private var showLibrary = false
    @State private var paper = WebPDFConverter.Layout.letter
    @State private var landscape = false

    static let types: [UTType] = {
        var t: [UTType] = [.rtf, .rtfd, .plainText, .html, .commaSeparatedText]
        for ext in ["docx", "doc", "xlsx", "xls", "pptx", "ppt", "pages", "numbers", "key", "odt", "md"] {
            if let u = UTType(filenameExtension: ext) { t.append(u) }
        }
        return t
    }()

    private var isText: Bool {
        ["docx", "rtf", "rtfd", "txt", "text", "md", "csv", "log", "json", "xml"].contains(file?.pathExtension.lowercased() ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Word, Excel, PowerPoint, Pages, Numbers, Keynote, RTF and text files.")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                if let f = file {
                    Panel(title: "Document") {
                        HStack(spacing: 12) {
                            Image(systemName: icon(f)).font(.title2).foregroundStyle(Theme.accent).frame(width: 40)
                            Text(f.lastPathComponent).font(.subheadline.weight(.medium)).lineLimit(2)
                            Spacer()
                            Button { file = nil } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(.secondary)
                        }
                    }
                    Panel(title: "Pages") {
                        Picker("Paper", selection: $paper) {
                            Text("Letter").tag(WebPDFConverter.Layout.letter)
                            Text("A4").tag(WebPDFConverter.Layout.a4)
                            if !isText { Text("Fit content").tag(WebPDFConverter.Layout.long) }
                        }
                        .pickerStyle(.segmented)
                        if paper != .long { Toggle("Landscape", isOn: $landscape) }
                    }
                } else {
                    Menu {
                        Button { showImporter = true } label: { Label("Files app", systemImage: "folder") }
                        Button { showLibrary = true } label: { Label("Ski PDF files", systemImage: "tray.full") }
                    } label: {
                        Label("Choose Document", systemImage: "plus.circle.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.iconTile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(16)
        }
        .toolBackground()
        .safeAreaInset(edge: .bottom) {
            if file != nil {
                PrimaryButton(title: "Convert to PDF", systemImage: "doc.text", busy: runner.busy, action: convert)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.types) { r in
            if case .success(let u) = r { file = try? Scratch.copyIn(u) }
        }
        .sheet(isPresented: $showLibrary) {
            LibraryPicker(filter: { !$0.isPDF && !$0.isImage }) { files in
                if let f = files.first { file = try? Scratch.copyIn(f.url) }
            }
        }
        .toolRunner(runner)
    }

    private func icon(_ u: URL) -> String {
        switch u.pathExtension.lowercased() {
        case "xlsx", "xls", "numbers", "csv": return "tablecells"
        case "pptx", "ppt", "key": return "rectangle.on.rectangle"
        default: return "doc.text"
        }
    }

    private func convert() {
        guard let f = file else { return }
        runner.busy = true
        let lay = paper, land = landscape, text = isText
        Task { @MainActor in
            do {
                let data: Data
                if text {
                    let attr = try TextPDFConverter.attributed(fromFile: f)
                    let base = lay.paper ?? CGSize(width: 612, height: 792)
                    data = TextPDFConverter.pdf(from: attr, paper: land ? CGSize(width: base.height, height: base.width) : base)
                } else {
                    data = try await WebPDFConverter().convert(file: f, layout: lay, landscape: land)
                }
                guard let doc = PDFDocument(data: data), doc.pageCount > 0 else { throw ToolError("This document couldn't be converted.") }
                let out = try PDFEngine.save(data, name: f.deletingPathExtension().lastPathComponent)
                runner.busy = false
                runner.result = ToolResult(files: [out], message: "Converted to a \(doc.pageCount)-page PDF.")
            } catch {
                runner.busy = false
                runner.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

// MARK: - OCR

struct OCRTool: View {
    enum Input: String, CaseIterable, Identifiable {
        case pdf = "PDF", images = "Photos / images"
        var id: String { rawValue }
    }

    @StateObject private var runner = ToolRunner()
    @State private var input = Input.pdf
    @State private var pdf: PickedPDF?
    @State private var images: [PickedImage] = []
    @State private var language = "auto"
    @State private var saveText = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Reads the words on scanned pages and photos, then makes a PDF you can search, select and copy.")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Picker("Input", selection: $input) { ForEach(Input.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                if input == .pdf {
                    if let p = pdf {
                        Panel(title: "PDF") { PickedPDFRow(pdf: p) { pdf = nil } }
                    } else {
                        PDFPicker { pdf = $0.first }
                    }
                } else {
                    if !images.isEmpty {
                        Panel(title: "\(images.count) image\(images.count == 1 ? "" : "s")") {
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach(images) { img in
                                        if let ui = UIImage(data: img.data, scale: 8) {
                                            Image(uiImage: ui).resizable().scaledToFill().frame(width: 56, height: 72).clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                    }
                                }
                            }
                            Button("Clear", role: .destructive) { images = [] }.font(.footnote)
                        }
                    }
                    ImagePicker(title: images.isEmpty ? "Choose Images" : "Add more") { images += $0 }
                }
                Panel(title: "Language") {
                    Picker("Language", selection: $language) {
                        Text("Detect automatically").tag("auto")
                        ForEach(OCREngine.languages, id: \.code) { Text($0.name).tag($0.code) }
                    }
                    Toggle("Also save the text as a .txt file", isOn: $saveText)
                }
            }
            .padding(16)
        }
        .toolBackground()
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Recognize Text", systemImage: "text.viewfinder", busy: runner.busy,
                          disabled: input == .pdf ? pdf == nil : images.isEmpty, action: run)
                .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .toolRunner(runner)
    }

    private func run() {
        let langs = language == "auto" ? [] : [language]
        let keepText = saveText
        if input == .pdf, let p = pdf {
            let doc = p.document, name = p.name
            runner.run { progress in
                let (data, text) = try OCREngine.searchable(doc, languages: langs, progress: progress)
                var files = [try PDFEngine.save(data, name: "\(name) searchable")]
                if keepText { files.append(try FileLibrary.shared.save(Data(text.utf8), name: "\(name).txt")) }
                let words = text.split { $0.isWhitespace || $0.isNewline }.count
                return ToolResult(files: files, message: words > 0 ? "Found \(words) words. The PDF is now searchable." : "No text was found on these pages.")
            }
        } else {
            let datas = images.map(\.data)
            runner.run { progress in
                let imgs = datas.compactMap(UIImage.init(data:))
                let (data, text) = try OCREngine.searchablePDF(images: imgs, languages: langs, quality: 0.8, progress: progress)
                var files = [try PDFEngine.save(data, name: "OCR")]
                if keepText { files.append(try FileLibrary.shared.save(Data(text.utf8), name: "OCR.txt")) }
                let words = text.split { $0.isWhitespace || $0.isNewline }.count
                return ToolResult(files: files, message: words > 0 ? "Found \(words) words." : "No text was found in these images.")
            }
        }
    }
}

// MARK: - Extract text

struct ExtractTextTool: View {
    @StateObject private var runner = ToolRunner()
    @State private var pdf: PickedPDF?
    @State private var text: String?
    @State private var working = false
    @State private var scanned = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            if let p = pdf {
                HStack {
                    PickedPDFRow(pdf: p) { pdf = nil; text = nil }
                }
                .padding(16)
                if working {
                    Spacer()
                    ProgressView(scanned ? "Reading the page images…" : "Getting text…")
                    Spacer()
                } else if let t = text {
                    if scanned {
                        Text("This PDF looks scanned, so the text was read with OCR.")
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                    }
                    ScrollView {
                        Text(t.isEmpty ? "No text found." : t)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    .background(Theme.card.opacity(0.4))
                    HStack(spacing: 12) {
                        Button {
                            UIPasteboard.general.string = t
                            copied = true
                        } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        Button {
                            let n = p.name
                            runner.run { _ in
                                let f = try FileLibrary.shared.save(Data(t.utf8), name: "\(n).txt")
                                return ToolResult(files: [f], message: "Saved the text as a .txt file.")
                            }
                        } label: { Label("Save .txt", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(16)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Pull all the text out of a PDF. Scanned PDFs are read with OCR automatically.")
                            .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        PDFPicker { picked in
                            pdf = picked.first
                            if let p = pdf { extract(p) }
                        }
                    }.padding(16)
                }
            }
        }
        .toolBackground()
        .toolRunner(runner)
    }

    private func extract(_ p: PickedPDF) {
        working = true
        copied = false
        let doc = p.document
        Task.detached(priority: .userInitiated) {
            if PDFEngine.looksScanned(doc) {
                await MainActor.run { scanned = true }
                let t = (try? OCREngine.searchable(doc, languages: [], progress: nil).1) ?? ""
                await MainActor.run { text = t; working = false }
            } else {
                let t = PDFEngine.text(of: doc)
                await MainActor.run { scanned = false; text = t; working = false }
            }
        }
    }
}
