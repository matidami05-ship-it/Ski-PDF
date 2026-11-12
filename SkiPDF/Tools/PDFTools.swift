import SwiftUI
import PDFKit

// MARK: - Merge

struct MergeTool: View {
    @StateObject private var runner = ToolRunner()
    @State private var pdfs: [PickedPDF] = []
    @State private var name = "Merged"

    var body: some View {
        List {
            Section {
                Text("Add two or more PDFs, drag them into order, then merge.").font(.subheadline).foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
            if !pdfs.isEmpty {
                Section("Order (\(pdfs.reduce(0) { $0 + $1.pageCount }) pages total)") {
                    ForEach(pdfs) { p in PickedPDFRow(pdf: p) }
                        .onMove { pdfs.move(fromOffsets: $0, toOffset: $1) }
                        .onDelete { pdfs.remove(atOffsets: $0) }
                }
            }
            Section {
                PDFPicker(title: pdfs.isEmpty ? "Choose PDFs" : "Add more PDFs", multiple: true) { pdfs += $0 }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            if pdfs.count >= 2 {
                Section("File name") { TextField("Name", text: $name) }
            }
        }
        .environment(\.editMode, .constant(pdfs.count > 1 ? .active : .inactive))
        .scrollContentBackground(.hidden)
        .toolBackground()
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Merge \(pdfs.count) PDFs", systemImage: "arrow.triangle.merge", busy: runner.busy, disabled: pdfs.count < 2) {
                let docs = pdfs.map(\.document)
                let n = name
                runner.run { _ in
                    let merged = PDFEngine.merge(docs)
                    let f = try PDFEngine.save(merged, name: n)
                    return ToolResult(files: [f], message: "Merged into one PDF with \(merged.pageCount) pages.")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .toolRunner(runner)
    }
}

// MARK: - Split

struct SplitTool: View {
    enum Mode: String, CaseIterable, Identifiable {
        case everyPage = "Every page", everyN = "Every N pages", ranges = "Custom ranges", half = "In half"
        var id: String { rawValue }
    }

    @StateObject private var runner = ToolRunner()
    @State private var pdf: PickedPDF?
    @State private var mode = Mode.everyN
    @State private var n = 2
    @State private var ranges = ""

    private func groups(_ count: Int) -> [[Int]]? {
        switch mode {
        case .everyPage: return (0..<count).map { [$0] }
        case .everyN: return stride(from: 0, to: count, by: max(1, n)).map { Array($0..<min(count, $0 + max(1, n))) }
        case .half:
            let h = (count + 1) / 2
            return count < 2 ? nil : [Array(0..<h), Array(h..<count)]
        case .ranges:
            let parts = ranges.split(separator: ",").map { String($0) }
            var out: [[Int]] = []
            for p in parts {
                guard let g = PageRange.parse(p, count: count) else { return nil }
                out.append(g)
            }
            return out.isEmpty ? nil : out
        }
    }

    var body: some View {
        SinglePDFToolLayout(pdf: $pdf, actionTitle: "Split", actionSymbol: "arrow.triangle.branch",
                            actionDisabled: pdf.map { groups($0.pageCount) == nil } ?? true, busy: runner.busy,
                            hint: "Break one PDF into several files.", action: run) {
            Panel(title: "How to split") {
                Picker("Mode", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.menu)
                switch mode {
                case .everyN:
                    Stepper("Every \(n) page\(n == 1 ? "" : "s")", value: $n, in: 1...max(1, (pdf?.pageCount ?? 2)))
                case .ranges:
                    TextField("e.g. 1-3, 4-6, 7-", text: $ranges)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numbersAndPunctuation)
                    Text("Each range separated by a comma becomes its own file.").font(.caption).foregroundStyle(.secondary)
                default: EmptyView()
                }
                if let p = pdf, let g = groups(p.pageCount) {
                    Text("Makes \(g.count) file\(g.count == 1 ? "" : "s").").font(.footnote).foregroundStyle(Theme.accent)
                } else if mode == .ranges && !ranges.isEmpty {
                    Text("Check the page numbers (this PDF has \(pdf?.pageCount ?? 0) pages).").font(.footnote).foregroundStyle(Theme.danger)
                }
            }
        }
        .toolRunner(runner)
    }

    private func run() {
        guard let p = pdf, let g = groups(p.pageCount) else { return }
        let doc = p.document, name = p.name
        runner.run { progress in
            var files: [LibraryFile] = []
            for (i, pages) in g.enumerated() {
                let part = PDFEngine.subset(doc, pages: pages)
                let label = pages.count == 1 ? "p\(pages[0] + 1)" : "p\(pages.first! + 1)-\(pages.last! + 1)"
                files.append(try PDFEngine.save(part, name: "\(name) \(label)"))
                progress(Double(i + 1) / Double(g.count))
            }
            return ToolResult(files: files, message: "Split into \(files.count) PDFs.")
        }
    }
}

// MARK: - Compress

struct CompressPDFTool: View {
    @StateObject private var runner = ToolRunner()
    @State private var pdf: PickedPDF?
    @State private var level = PDFEngine.CompressLevel.medium
    @State private var gray = false

    var body: some View {
        SinglePDFToolLayout(pdf: $pdf, actionTitle: "Compress", actionSymbol: "arrow.down.right.and.arrow.up.left", busy: runner.busy,
                            hint: "Make a PDF smaller to email or upload.", action: run) {
            Panel(title: "Strength") {
                Picker("Level", selection: $level) { ForEach(PDFEngine.CompressLevel.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                Text(level.detail).font(.footnote).foregroundStyle(.secondary)
                Toggle("Black & white (smaller)", isOn: $gray)
            }
            if let p = pdf, let size = try? p.url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                Text("Current size: \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toolRunner(runner)
    }

    private func run() {
        guard let p = pdf else { return }
        let doc = p.document, name = p.name, lvl = level, g = gray
        let before = (try? p.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        runner.run { progress in
            let data = try PDFEngine.compress(doc, level: lvl, grayscale: g, progress: progress)
            let f = try PDFEngine.save(data, name: "\(name) compressed")
            let saved = before > 0 ? Int((1 - Double(data.count) / Double(before)) * 100) : 0
            let msg = saved > 0
                ? "\(ByteCountFormatter.string(fromByteCount: Int64(before), countStyle: .file)) → \(f.sizeText) (\(saved)% smaller)."
                : "Done. This PDF was already compact (\(f.sizeText)); try a stronger level."
            return ToolResult(files: [f], message: msg)
        }
    }
}

// MARK: - PDF to images

struct PDFToImagesTool: View {
    @StateObject private var runner = ToolRunner()
    @State private var pdf: PickedPDF?
    @State private var format = ImageEngine.Format.jpeg
    @State private var dpi = 150.0
    @State private var pages = ""

    var body: some View {
        SinglePDFToolLayout(pdf: $pdf, actionTitle: "Make Images", actionSymbol: "photo.on.rectangle.angled", busy: runner.busy,
                            hint: "Save pages as pictures.", action: run) {
            Panel(title: "Format") {
                Picker("Format", selection: $format) { ForEach(ImageEngine.Format.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                VStack(alignment: .leading) {
                    Text("Quality: \(Int(dpi)) dpi" + (dpi >= 300 ? " (print)" : dpi <= 96 ? " (screen)" : ""))
                    Slider(value: $dpi, in: 72...300, step: 6)
                }
            }
            Panel(title: "Pages") {
                TextField("All pages (or e.g. 1-3, 5)", text: $pages).textFieldStyle(.roundedBorder).keyboardType(.numbersAndPunctuation)
            }
        }
        .toolRunner(runner)
    }

    private func run() {
        guard let p = pdf else { return }
        guard let list = PageRange.parse(pages, count: p.pageCount) else { runner.error = "Check the page numbers."; return }
        let doc = p.document, name = p.name, fmt = format, d = CGFloat(dpi)
        runner.run { progress in
            var files: [LibraryFile] = []
            for (n, i) in list.enumerated() {
                guard let page = doc.page(at: i) else { continue }
                try autoreleasepool {
                    let img = PDFEngine.image(of: page, dpi: d)
                    guard let cg = img.cgImage, let data = ImageEngine.encode(cg, as: fmt, quality: 0.88) else { throw ToolError("Couldn't make image for page \(i + 1).") }
                    files.append(try FileLibrary.shared.save(data, name: "\(name) p\(i + 1).\(fmt.ext)"))
                }
                progress(Double(n + 1) / Double(list.count))
            }
            return ToolResult(files: files, message: "Saved \(files.count) image\(files.count == 1 ? "" : "s").", images: files.map(\.url))
        }
    }
}

// MARK: - Images to PDF

struct ImagesToPDFTool: View {
    @StateObject private var runner = ToolRunner()
    @State private var images: [PickedImage] = []
    @State private var pageSize = PDFEngine.PageSize.a4
    @State private var margin = 20.0
    @State private var quality = 0.8
    @State private var ocr = false
    @State private var name = "Images"

    var body: some View {
        List {
            if !images.isEmpty {
                Section("Pages — drag to reorder") {
                    ForEach(images) { img in
                        HStack(spacing: 12) {
                            if let ui = UIImage(data: img.data, scale: 8) {
                                Image(uiImage: ui).resizable().scaledToFill().frame(width: 44, height: 56).clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            Text(img.name).font(.subheadline).lineLimit(1)
                        }
                    }
                    .onMove { images.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { images.remove(atOffsets: $0) }
                }
            }
            Section {
                ImagePicker(title: images.isEmpty ? "Choose Images" : "Add more images") { images += $0 }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            if !images.isEmpty {
                Section("Page") {
                    Picker("Page size", selection: $pageSize) { ForEach(PDFEngine.PageSize.allCases) { Text($0.rawValue).tag($0) } }
                    VStack(alignment: .leading) {
                        Text("Margin: \(Int(margin)) pt")
                        Slider(value: $margin, in: 0...72, step: 2)
                    }
                    VStack(alignment: .leading) {
                        Text("Image quality: \(Int(quality * 100))%")
                        Slider(value: $quality, in: 0.3...1)
                    }
                    Toggle("Make text searchable (OCR)", isOn: $ocr)
                }
                Section("File name") { TextField("Name", text: $name) }
            }
        }
        .environment(\.editMode, .constant(images.count > 1 ? .active : .inactive))
        .scrollContentBackground(.hidden)
        .toolBackground()
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Create PDF", systemImage: "doc.richtext", busy: runner.busy, disabled: images.isEmpty) {
                let datas = images.map(\.data), size = pageSize, m = CGFloat(margin), q = CGFloat(quality), n = name, doOCR = ocr
                runner.run { progress in
                    let uiImages = datas.compactMap(UIImage.init(data:))
                    var data: Data
                    if doOCR {
                        let pdf = PDFEngine.pdf(from: uiImages, pageSize: size, margin: m, quality: q, progress: { progress($0 * 0.4) })
                        guard let doc = PDFDocument(data: pdf) else { throw ToolError("Couldn't create the PDF.") }
                        data = try OCREngine.searchable(doc, languages: [], progress: { progress(0.4 + $0 * 0.6) }).0
                    } else {
                        data = PDFEngine.pdf(from: uiImages, pageSize: size, margin: m, quality: q, progress: progress)
                    }
                    let f = try PDFEngine.save(data, name: n)
                    return ToolResult(files: [f], message: "Made a \(uiImages.count)-page PDF (\(f.sizeText)).")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .toolRunner(runner)
    }
}

// MARK: - Reorder / Rotate / Delete / Extract pages

struct PageEditTool: View {
    let tool: Tool
    @StateObject private var runner = ToolRunner()
    @State private var pdf: PickedPDF?
    @State private var order: [Int] = []
    @State private var selected = Set<Int>()
    @State private var rotation: [Int: Int] = [:]
    @State private var thumbs: [Int: UIImage] = [:]
    @State private var rangeText = ""

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        Group {
            if let p = pdf {
                editor(p)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        Text(tool.subtitle).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        PDFPicker { picked in
                            guard let p = picked.first else { return }
                            pdf = p
                            order = Array(0..<p.pageCount)
                            selected = []
                            rotation = [:]
                            loadThumbs(p)
                        }
                    }.padding(16)
                }
            }
        }
        .toolBackground()
        .toolRunner(runner)
    }

    @ViewBuilder
    private func editor(_ p: PickedPDF) -> some View {
        VStack(spacing: 0) {
            if tool == .reorder {
                List {
                    ForEach(order, id: \.self) { i in
                        HStack(spacing: 14) {
                            thumb(i).frame(width: 52, height: 68)
                            Text("Page \(i + 1)").font(.subheadline)
                        }
                    }
                    .onMove { order.move(fromOffsets: $0, toOffset: $1) }
                }
                .environment(\.editMode, .constant(.active))
                .scrollContentBackground(.hidden)
            } else {
                selectionBar(p)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(order, id: \.self) { i in
                            Button { toggle(i) } label: {
                                VStack(spacing: 6) {
                                    thumb(i)
                                        .rotationEffect(.degrees(Double(rotation[i] ?? 0)))
                                        .frame(height: 120)
                                        .overlay(alignment: .topTrailing) {
                                            Image(systemName: selected.contains(i) ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .foregroundStyle(selected.contains(i) ? Theme.accent : .white.opacity(0.7))
                                                .padding(4)
                                        }
                                        .opacity(tool == .deletePages && selected.contains(i) ? 0.35 : 1)
                                    Text("\(i + 1)").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(6)
                                .background(selected.contains(i) ? Theme.iconTile : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if tool == .rotate {
                    HStack(spacing: 12) {
                        Button { rotate(-90) } label: { Label("Left", systemImage: "rotate.left").frame(maxWidth: .infinity) }
                        Button { rotate(90) } label: { Label("Right", systemImage: "rotate.right").frame(maxWidth: .infinity) }
                        Button { rotate(180) } label: { Label("180°", systemImage: "arrow.2.squarepath").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.bordered)
                    Text(selected.isEmpty ? "Rotates all pages. Tap pages to rotate only some." : "Rotates \(selected.count) selected page\(selected.count == 1 ? "" : "s").")
                        .font(.caption).foregroundStyle(.secondary)
                }
                PrimaryButton(title: actionTitle, systemImage: tool.symbol, busy: runner.busy, disabled: !canRun) { run(p) }
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
            .background(Theme.background.opacity(0.95))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Change PDF") { pdf = nil }
            }
        }
    }

    private func selectionBar(_ p: PickedPDF) -> some View {
        HStack {
            TextField("Select pages, e.g. 1-3, 7", text: $rangeText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .onSubmit { if let r = PageRange.parse(rangeText, count: p.pageCount) { selected = Set(r) } }
            Button(selected.count == p.pageCount ? "None" : "All") {
                selected = selected.count == p.pageCount ? [] : Set(0..<p.pageCount)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var actionTitle: String {
        switch tool {
        case .reorder: return "Save New Order"
        case .rotate: return "Save Rotated PDF"
        case .deletePages: return selected.isEmpty ? "Select pages to delete" : "Delete \(selected.count) page\(selected.count == 1 ? "" : "s")"
        default: return selected.isEmpty ? "Select pages to extract" : "Extract \(selected.count) page\(selected.count == 1 ? "" : "s")"
        }
    }

    private var canRun: Bool {
        guard let p = pdf else { return false }
        switch tool {
        case .reorder: return order != Array(0..<p.pageCount)
        case .rotate: return rotation.values.contains { $0 % 360 != 0 }
        case .deletePages: return !selected.isEmpty && selected.count < p.pageCount
        default: return !selected.isEmpty
        }
    }

    private func toggle(_ i: Int) {
        if selected.contains(i) { selected.remove(i) } else { selected.insert(i) }
    }

    private func rotate(_ d: Int) {
        let targets = selected.isEmpty ? Set(order) : selected
        withAnimation { for i in targets { rotation[i] = (rotation[i] ?? 0) + d } }
    }

    private func thumb(_ i: Int) -> some View {
        Group {
            if let t = thumbs[i] {
                Image(uiImage: t).resizable().scaledToFit()
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(radius: 2)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Theme.card)
            }
        }
    }

    private func loadThumbs(_ p: PickedPDF) {
        thumbs = [:]
        let doc = p.document
        Task.detached(priority: .userInitiated) {
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                let t = page.thumbnail(of: CGSize(width: 180, height: 240), for: .cropBox)
                await MainActor.run { thumbs[i] = t }
            }
        }
    }

    private func run(_ p: PickedPDF) {
        let doc = p.document, name = p.name, t = tool
        let ord = order, sel = selected, rot = rotation
        runner.run { _ in
            switch t {
            case .reorder:
                let f = try PDFEngine.save(PDFEngine.subset(doc, pages: ord), name: "\(name) reordered")
                return ToolResult(files: [f], message: "Pages saved in the new order.")
            case .rotate:
                let f = try PDFEngine.save(PDFEngine.rotated(doc, by: rot), name: "\(name) rotated")
                return ToolResult(files: [f], message: "Rotated \(rot.values.filter { $0 % 360 != 0 }.count) page(s).")
            case .deletePages:
                let keep = (0..<doc.pageCount).filter { !sel.contains($0) }
                let f = try PDFEngine.save(PDFEngine.subset(doc, pages: keep), name: "\(name) edited")
                return ToolResult(files: [f], message: "Removed \(sel.count) page(s); \(keep.count) left.")
            default:
                let pages = sel.sorted()
                let f = try PDFEngine.save(PDFEngine.subset(doc, pages: pages), name: "\(name) extract")
                return ToolResult(files: [f], message: "Copied \(pages.count) page(s) into a new PDF.")
            }
        }
    }
}

// MARK: - Print Studio

struct PrintStudioTool: View {
    @State private var pdf: PickedPDF?
    @State private var pages = ""
    @State private var perSheet = 1
    @State private var paper = PDFEngine.PageSize.letter
    @State private var borders = true
    @State private var grayscale = false
    @State private var duplex = false
    @State private var error: String?

    var body: some View {
        SinglePDFToolLayout(pdf: $pdf, actionTitle: "Print…", actionSymbol: "printer.fill", busy: false,
                            hint: "Choose pages and layout, then pick your printer.", action: printNow) {
            Panel(title: "Pages") {
                TextField("All pages (or e.g. 1-4, 9)", text: $pages).textFieldStyle(.roundedBorder).keyboardType(.numbersAndPunctuation)
            }
            Panel(title: "Layout") {
                Picker("Pages per sheet", selection: $perSheet) {
                    ForEach([1, 2, 4, 6, 9], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                if perSheet > 1 {
                    Picker("Paper", selection: $paper) {
                        Text("Letter").tag(PDFEngine.PageSize.letter)
                        Text("A4").tag(PDFEngine.PageSize.a4)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Border around each page", isOn: $borders)
                }
            }
            Panel(title: "Printer options") {
                Toggle("Black & white", isOn: $grayscale)
                Toggle("Two-sided", isOn: $duplex)
            }
        }
        .alert(error ?? "", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK", role: .cancel) {} }
    }

    private func printNow() {
        guard let p = pdf else { return }
        guard let list = PageRange.parse(pages, count: p.pageCount) else { error = "Check the page numbers."; return }
        let data: Data
        if perSheet == 1 {
            if list.count == p.pageCount, let d = p.document.dataRepresentation() { data = d }
            else { data = PDFEngine.subset(p.document, pages: list).dataRepresentation() ?? Data() }
        } else {
            data = PDFEngine.nUp(p.document, pages: list, perSheet: perSheet, sheet: paper.size ?? CGSize(width: 612, height: 792), borders: borders)
        }
        let pc = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = p.name
        info.outputType = grayscale ? .grayscale : .general
        info.duplex = duplex ? .longEdge : .none
        pc.printInfo = info
        pc.printingItem = data
        pc.present(animated: true)
    }
}
