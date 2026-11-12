import SwiftUI

enum Tool: String, CaseIterable, Identifiable, Hashable {
    // PDF
    case merge, split, compress, pdfToImages, imagesToPDF
    // Organize
    case reorder, rotate, deletePages, extractPages, print
    // Convert
    case htmlToPDF, scan, docToPDF, ocr, extractText
    // Security
    case lock, unlock, watermark, sign, fillForms, flatten
    // Image tools
    case compressImage, resizeImage, convertImage, stripMetadata
    // View & export
    case view, pageNumbers, metadata

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: return "Merge PDF"
        case .split: return "Split PDF"
        case .compress: return "Compress PDF"
        case .pdfToImages: return "PDF to Images"
        case .imagesToPDF: return "Images to PDF"
        case .reorder: return "Reorder Pages"
        case .rotate: return "Rotate Pages"
        case .deletePages: return "Delete Pages"
        case .extractPages: return "Extract Pages"
        case .print: return "Print Studio"
        case .htmlToPDF: return "HTML to PDF"
        case .scan: return "Scan to PDF"
        case .docToPDF: return "Doc to PDF"
        case .ocr: return "OCR"
        case .extractText: return "Extract Text"
        case .lock: return "Lock PDF"
        case .unlock: return "Unlock PDF"
        case .watermark: return "Add Watermark"
        case .sign: return "Sign PDF"
        case .fillForms: return "Fill Forms"
        case .flatten: return "Flatten PDF"
        case .compressImage: return "Compress Image"
        case .resizeImage: return "Resize Image"
        case .convertImage: return "Convert Format"
        case .stripMetadata: return "Strip Metadata"
        case .view: return "View PDF"
        case .pageNumbers: return "Page Numbers"
        case .metadata: return "View Metadata"
        }
    }

    var symbol: String {
        switch self {
        case .merge: return "arrow.triangle.merge"
        case .split: return "arrow.triangle.branch"
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .pdfToImages: return "photo.on.rectangle.angled"
        case .imagesToPDF: return "photo.fill"
        case .reorder: return "arrow.up.arrow.down"
        case .rotate: return "arrow.clockwise"
        case .deletePages: return "trash.fill"
        case .extractPages: return "doc.on.doc.fill"
        case .print: return "printer.fill"
        case .htmlToPDF: return "globe"
        case .scan: return "camera.fill"
        case .docToPDF: return "doc.text.fill"
        case .ocr: return "text.viewfinder"
        case .extractText: return "textformat.size"
        case .lock: return "lock.fill"
        case .unlock: return "lock.open.fill"
        case .watermark: return "drop.fill"
        case .sign: return "signature"
        case .fillForms: return "square.and.pencil"
        case .flatten: return "square.3.layers.3d.down.right"
        case .compressImage: return "arrow.down.right.and.arrow.up.left.circle"
        case .resizeImage: return "aspectratio"
        case .convertImage: return "crop.rotate"
        case .stripMetadata: return "eye.slash.fill"
        case .view: return "doc.richtext.fill"
        case .pageNumbers: return "list.number"
        case .metadata: return "info.circle.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .merge: return "Combine several PDFs into one, in any order."
        case .split: return "Break a PDF into separate files."
        case .compress: return "Make a PDF smaller to email or upload."
        case .pdfToImages: return "Save each page as a JPEG or PNG."
        case .imagesToPDF: return "Turn photos into a PDF."
        case .reorder: return "Drag pages into a new order."
        case .rotate: return "Turn pages that are sideways or upside down."
        case .deletePages: return "Remove pages you don't need."
        case .extractPages: return "Copy chosen pages into a new PDF."
        case .print: return "Print with page ranges and pages per sheet."
        case .htmlToPDF: return "Save a web page or HTML file as a PDF."
        case .scan: return "Scan paper with the camera, edges cleaned up."
        case .docToPDF: return "Word, Excel, PowerPoint, RTF or text to PDF."
        case .ocr: return "Make scanned pages searchable and copyable."
        case .extractText: return "Pull all the text out of a PDF."
        case .lock: return "Protect a PDF with a password."
        case .unlock: return "Remove a PDF's password."
        case .watermark: return "Stamp text across every page."
        case .sign: return "Draw your signature and place it on the page."
        case .fillForms: return "Type into PDF form fields and tick boxes."
        case .flatten: return "Bake forms and markup into the page."
        case .compressImage: return "Shrink photos while keeping them sharp."
        case .resizeImage: return "Change image dimensions."
        case .convertImage: return "JPEG, PNG or HEIC."
        case .stripMetadata: return "Remove location, camera and date info."
        case .view: return "Read, search and mark up PDFs."
        case .pageNumbers: return "Add page numbers to every page."
        case .metadata: return "See and edit title, author and more."
        }
    }
}

struct ToolSection: Identifiable {
    let title: String
    let tools: [Tool]
    var id: String { title }

    static let all: [ToolSection] = [
        ToolSection(title: "PDF", tools: [.merge, .split, .compress, .pdfToImages, .imagesToPDF]),
        ToolSection(title: "Organize", tools: [.reorder, .rotate, .deletePages, .extractPages, .print]),
        ToolSection(title: "Convert", tools: [.htmlToPDF, .scan, .docToPDF, .ocr, .extractText]),
        ToolSection(title: "Security", tools: [.lock, .unlock, .watermark, .sign, .fillForms, .flatten]),
        ToolSection(title: "Image Tools", tools: [.compressImage, .resizeImage, .convertImage, .stripMetadata]),
        ToolSection(title: "View & Export", tools: [.view, .pageNumbers, .metadata]),
    ]
}

struct ToolsView: View {
    @State private var path = NavigationPath()
    @State private var search = ""
    @State private var showAbout = false

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: 12)]

    private var sections: [ToolSection] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return ToolSection.all }
        return ToolSection.all.compactMap { s in
            let t = s.tools.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.subtitle.localizedCaseInsensitiveContains(q) }
            return t.isEmpty ? nil : ToolSection(title: s.title, tools: t)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                Text(section.title).font(.title3.weight(.semibold)).foregroundStyle(Theme.section)
                                Rectangle().fill(Theme.divider).frame(height: 1)
                            }
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(section.tools) { tool in
                                    NavigationLink(value: tool) { ToolCard(tool: tool) }
                                        .buttonStyle(CardButtonStyle())
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .toolBackground()
            .searchable(text: $search, prompt: "Find a tool")
            .navigationTitle("Ski PDF")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAbout = true } label: { Image(systemName: "gearshape.fill") }
                }
            }
            .navigationDestination(for: Tool.self) { tool in
                ToolScreen(tool: tool)
            }
            .sheet(isPresented: $showAbout) { AboutView() }
        }
    }
}

struct ToolCard: View {
    let tool: Tool
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: tool.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 48, height: 48)
                .background(Theme.iconTile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(tool.title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 116)
        .padding(.horizontal, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Picks the right screen for a tool.
struct ToolScreen: View {
    let tool: Tool
    var body: some View {
        Group {
            switch tool {
            case .merge: MergeTool()
            case .split: SplitTool()
            case .compress: CompressPDFTool()
            case .pdfToImages: PDFToImagesTool()
            case .imagesToPDF: ImagesToPDFTool()
            case .reorder, .rotate, .deletePages, .extractPages: PageEditTool(tool: tool)
            case .print: PrintStudioTool()
            case .htmlToPDF: HTMLToPDFTool()
            case .scan: ScanTool()
            case .docToPDF: DocToPDFTool()
            case .ocr: OCRTool()
            case .extractText: ExtractTextTool()
            case .lock: LockTool()
            case .unlock: UnlockTool()
            case .watermark: WatermarkTool()
            case .sign: SignTool()
            case .fillForms: FillFormsTool()
            case .flatten: FlattenTool()
            case .compressImage, .resizeImage, .convertImage, .stripMetadata: ImageTool(tool: tool)
            case .view: ViewPDFTool()
            case .pageNumbers: PageNumbersTool()
            case .metadata: MetadataTool()
            }
        }
        .navigationTitle(tool.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var library: FileLibrary
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "doc.richtext.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading) {
                            Text("Ski PDF").font(.headline)
                            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Your files") {
                    LabeledContent("Files saved", value: "\(library.files.count)")
                    LabeledContent("Space used", value: ByteCountFormatter.string(fromByteCount: library.files.reduce(0) { $0 + $1.size }, countStyle: .file))
                    Text("Everything you make is saved in the Files tab and in the Files app under On My iPhone › Ski PDF.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Text("All tools run on your iPhone. Your documents are never uploaded anywhere.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
