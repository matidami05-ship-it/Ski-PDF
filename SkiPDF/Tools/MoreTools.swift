import SwiftUI
import PDFKit

// MARK: - Page numbers

struct PageNumbersTool: View {
    @StateObject private var runner = ToolRunner()
    @State private var pdf: PickedPDF?
    @State private var format = PDFEngine.NumberFormat.plain
    @State private var position = PDFEngine.NumberPosition.bottomCenter
    @State private var start = 1
    @State private var fontSize = 11.0
    @State private var skipFirst = false
    @State private var color = Color.black
    @State private var preview: UIImage?

    var body: some View {
        SinglePDFToolLayout(pdf: $pdf, actionTitle: "Add Page Numbers", actionSymbol: "list.number", busy: runner.busy, action: run) {
            if let preview {
                Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 240).shadow(radius: 4)
            }
            Panel(title: "Style") {
                Picker("Format", selection: $format) { ForEach(PDFEngine.NumberFormat.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Position", selection: $position) { ForEach(PDFEngine.NumberPosition.allCases) { Text($0.rawValue).tag($0) } }
                Stepper("Size \(Int(fontSize)) pt", value: $fontSize, in: 6...36)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
            }
            Panel(title: "Numbering") {
                Stepper("Start at \(start)", value: $start, in: 0...9999)
                Toggle("Skip the first page (cover)", isOn: $skipFirst)
            }
        }
        .onChange(of: pdf?.id) { _, _ in updatePreview() }
        .onChange(of: format) { _, _ in updatePreview() }
        .onChange(of: position) { _, _ in updatePreview() }
        .onChange(of: fontSize) { _, _ in updatePreview() }
        .onChange(of: start) { _, _ in updatePreview() }
        .onChange(of: color) { _, _ in updatePreview() }
        .onChange(of: skipFirst) { _, _ in updatePreview() }
        .toolRunner(runner)
    }

    private func label(for i: Int, total: Int) -> String? {
        if skipFirst && i == 0 { return nil }
        let n = start + i - (skipFirst ? 1 : 0)
        let t = total - (skipFirst ? 1 : 0) + start - 1
        return format.text(n, total: t)
    }

    private func updatePreview() {
        guard let d = pdf?.document else { preview = nil; return }
        let idx = skipFirst && d.pageCount > 1 ? 1 : 0
        guard let page = d.page(at: idx) else { return }
        let size = PDFEngine.displaySize(page)
        let s = 300 / max(size.width, size.height)
        let text = label(for: idx, total: d.pageCount)
        let fs = CGFloat(fontSize), pos = position, col = UIColor(color)
        preview = UIGraphicsImageRenderer(size: CGSize(width: size.width * s, height: size.height * s)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(ctx.format.bounds)
            ctx.cgContext.scaleBy(x: s, y: s)
            PDFEngine.drawPage(page, in: CGRect(origin: .zero, size: size), context: ctx.cgContext)
            if let text { PDFEngine.drawPageNumber(text, position: pos, fontSize: fs, color: col, margin: 28, size: size, cg: ctx.cgContext) }
        }
    }

    private func run() {
        guard let p = pdf else { return }
        let doc = p.document, name = p.name, total = p.pageCount
        let labels = (0..<total).map { label(for: $0, total: total) }
        let fs = CGFloat(fontSize), pos = position, col = UIColor(color)
        runner.run { progress in
            let data = PDFEngine.redraw(doc, progress: progress) { i, size, cg in
                if let t = labels[i] { PDFEngine.drawPageNumber(t, position: pos, fontSize: fs, color: col, margin: 28, size: size, cg: cg) }
            }
            let f = try PDFEngine.save(data, name: "\(name) numbered")
            return ToolResult(files: [f], message: "Page numbers added.")
        }
    }
}

// MARK: - Metadata

struct MetadataTool: View {
    @StateObject private var runner = ToolRunner()
    @State private var pdf: PickedPDF?
    @State private var title = ""
    @State private var author = ""
    @State private var subject = ""
    @State private var keywords = ""
    @State private var creator = ""
    @State private var clearAll = false

    var body: some View {
        SinglePDFToolLayout(pdf: $pdf, actionTitle: "Save Copy with Changes", actionSymbol: "square.and.arrow.down", busy: runner.busy, action: run) {
            if let p = pdf {
                Panel(title: "About this PDF") {
                    info("Pages", "\(p.pageCount)")
                    if let s = try? p.url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        info("File size", ByteCountFormatter.string(fromByteCount: Int64(s), countStyle: .file))
                    }
                    info("PDF version", "\(p.document.majorVersion).\(p.document.minorVersion)")
                    if let page = p.document.page(at: 0) {
                        let sz = PDFEngine.displaySize(page)
                        info("Page size", paperName(sz))
                    }
                    info("Password", p.document.isEncrypted ? "Yes" : "No")
                    info("Text inside", PDFEngine.looksScanned(p.document) ? "Little or none (scanned?)" : "Yes")
                    let a = p.document.documentAttributes ?? [:]
                    if let d = a[PDFDocumentAttribute.creationDateAttribute] as? Date { info("Created", d.formatted(date: .abbreviated, time: .shortened)) }
                    if let d = a[PDFDocumentAttribute.modificationDateAttribute] as? Date { info("Modified", d.formatted(date: .abbreviated, time: .shortened)) }
                    if let s = a[PDFDocumentAttribute.producerAttribute] as? String, !s.isEmpty { info("Producer", s) }
                }
                Panel(title: "Details (editable)") {
                    field("Title", $title)
                    field("Author", $author)
                    field("Subject", $subject)
                    field("Keywords", $keywords)
                    field("Creator app", $creator)
                    Toggle("Remove all details", isOn: $clearAll)
                }
            }
        }
        .onChange(of: pdf?.id) { _, _ in loadFields() }
        .toolRunner(runner)
    }

    private func info(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.subheadline)
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text).textFieldStyle(.roundedBorder).disabled(clearAll)
        }
    }

    private func paperName(_ s: CGSize) -> String {
        let w = min(s.width, s.height), h = max(s.width, s.height)
        let name: String
        if abs(w - 612) < 4 && abs(h - 792) < 4 { name = "Letter" }
        else if abs(w - 595) < 4 && abs(h - 842) < 4 { name = "A4" }
        else if abs(w - 612) < 4 && abs(h - 1008) < 4 { name = "Legal" }
        else { name = "" }
        let inches = String(format: "%.1f × %.1f in", s.width / 72, s.height / 72)
        return name.isEmpty ? inches : "\(name) (\(inches))"
    }

    private func loadFields() {
        let a = pdf?.document.documentAttributes ?? [:]
        title = a[PDFDocumentAttribute.titleAttribute] as? String ?? ""
        author = a[PDFDocumentAttribute.authorAttribute] as? String ?? ""
        subject = a[PDFDocumentAttribute.subjectAttribute] as? String ?? ""
        if let k = a[PDFDocumentAttribute.keywordsAttribute] as? [String] { keywords = k.joined(separator: ", ") }
        else { keywords = a[PDFDocumentAttribute.keywordsAttribute] as? String ?? "" }
        creator = a[PDFDocumentAttribute.creatorAttribute] as? String ?? ""
        clearAll = false
    }

    private func run() {
        guard let p = pdf else { return }
        let doc = PDFEngine.subset(p.document, pages: Array(0..<p.pageCount))
        var attrs: [AnyHashable: Any] = [:]
        if !clearAll {
            if !title.isEmpty { attrs[PDFDocumentAttribute.titleAttribute] = title }
            if !author.isEmpty { attrs[PDFDocumentAttribute.authorAttribute] = author }
            if !subject.isEmpty { attrs[PDFDocumentAttribute.subjectAttribute] = subject }
            let kw = keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !kw.isEmpty { attrs[PDFDocumentAttribute.keywordsAttribute] = kw }
            if !creator.isEmpty { attrs[PDFDocumentAttribute.creatorAttribute] = creator }
        }
        doc.documentAttributes = attrs
        let name = p.name, cleared = clearAll
        runner.run { _ in
            let f = try PDFEngine.save(doc, name: "\(name) info")
            return ToolResult(files: [f], message: cleared ? "Saved a copy with the details removed." : "Saved a copy with the new details.")
        }
    }
}

// MARK: - Image tools

struct ImageTool: View {
    let tool: Tool
    @StateObject private var runner = ToolRunner()
    @State private var images: [PickedImage] = []
    // compress
    @State private var quality = 0.6
    @State private var limitSize = true
    @State private var maxSide = 2048.0
    // resize
    @State private var resizeByPercent = true
    @State private var percent = 50.0
    @State private var targetWidth = ""
    @State private var targetHeight = ""
    // convert
    @State private var format = ImageEngine.Format.jpeg
    // strip / general
    @State private var keepMetadata = true

    var body: some View {
        List {
            Section {
                Text(tool.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
            if !images.isEmpty {
                Section("\(images.count) image\(images.count == 1 ? "" : "s")") {
                    ForEach(images) { img in row(img) }
                        .onDelete { images.remove(atOffsets: $0) }
                }
            }
            Section {
                ImagePicker(title: images.isEmpty ? "Choose Images" : "Add more") { images += $0 }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            if !images.isEmpty { options }
        }
        .scrollContentBackground(.hidden)
        .toolBackground()
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: actionTitle, systemImage: tool.symbol, busy: runner.busy, disabled: images.isEmpty || !valid, action: run)
                .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .toolRunner(runner)
    }

    private var actionTitle: String {
        switch tool {
        case .compressImage: return "Compress"
        case .resizeImage: return "Resize"
        case .convertImage: return "Convert to \(format.rawValue)"
        default: return "Remove Metadata"
        }
    }

    private var valid: Bool {
        if tool == .resizeImage && !resizeByPercent { return Int(targetWidth) != nil || Int(targetHeight) != nil }
        return true
    }

    private func row(_ img: PickedImage) -> some View {
        let info = ImageEngine.info(img.data)
        return HStack(spacing: 12) {
            if let ui = UIImage(data: img.data, scale: 10) {
                Image(uiImage: ui).resizable().scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(img.name).font(.subheadline).lineLimit(1)
                if let i = info {
                    Text("\(i.pixelWidth) × \(i.pixelHeight) · \(ByteCountFormatter.string(fromByteCount: Int64(i.bytes), countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary)
                    if tool == .stripMetadata {
                        let found = [i.hasGPS ? "location" : nil, i.camera, i.date.map { "date \($0)" }].compactMap { $0 }
                        Text(found.isEmpty ? "No personal info found" : "Has: " + found.joined(separator: ", "))
                            .font(.caption).foregroundStyle(i.hasGPS ? Color.orange : .secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var options: some View {
        switch tool {
        case .compressImage:
            Section("Compression") {
                VStack(alignment: .leading) {
                    Text("Quality \(Int(quality * 100))%" + (quality < 0.4 ? " (small, softer)" : quality > 0.8 ? " (large, sharp)" : ""))
                    Slider(value: $quality, in: 0.2...0.95)
                }
                Toggle("Limit size", isOn: $limitSize)
                if limitSize {
                    Picker("Longest side", selection: $maxSide) {
                        Text("1280 px").tag(1280.0); Text("2048 px").tag(2048.0); Text("3000 px").tag(3000.0); Text("4096 px").tag(4096.0)
                    }
                }
                Toggle("Keep camera info", isOn: $keepMetadata)
                Text("Saved as JPEG.").font(.caption).foregroundStyle(.secondary)
            }
        case .resizeImage:
            Section("New size") {
                Picker("By", selection: $resizeByPercent) { Text("Percent").tag(true); Text("Pixels").tag(false) }
                    .pickerStyle(.segmented)
                if resizeByPercent {
                    VStack(alignment: .leading) {
                        Text("\(Int(percent))% of original")
                        Slider(value: $percent, in: 5...100, step: 5)
                    }
                } else {
                    HStack {
                        TextField("Width", text: $targetWidth).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        Text("×")
                        TextField("Height", text: $targetHeight).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    }
                    Text("Fill in one or both. The picture keeps its shape and fits inside.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Keep camera info", isOn: $keepMetadata)
            }
        case .convertImage:
            Section("Convert to") {
                Picker("Format", selection: $format) { ForEach(ImageEngine.Format.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                if format.lossy {
                    VStack(alignment: .leading) {
                        Text("Quality \(Int(quality * 100))%")
                        Slider(value: $quality, in: 0.3...1)
                    }
                }
                Toggle("Keep camera info", isOn: $keepMetadata)
            }
        default:
            Section {
                Text("Removes location (GPS), camera and lens details, dates and editing history. The picture itself is unchanged.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func run() {
        let items = images, t = tool
        let q = CGFloat(quality), lim = limitSize ? Int(maxSide) : nil
        let byPct = resizeByPercent, pct = percent / 100, tw = Int(targetWidth), th = Int(targetHeight)
        let fmt = format, keep = keepMetadata
        runner.run { progress in
            var files: [LibraryFile] = []
            var before = 0, after = 0
            for (n, item) in items.enumerated() {
                try autoreleasepool {
                    let src = ImageEngine.Format.of(item.data)
                    let info = ImageEngine.info(item.data)
                    let longest = max(info?.pixelWidth ?? 0, info?.pixelHeight ?? 0)
                    var maxPixel: Int? = nil
                    var outFormat = src
                    var outQuality: CGFloat = 0.92
                    var suffix = ""
                    var meta: [CFString: Any]? = nil
                    switch t {
                    case .compressImage:
                        maxPixel = lim
                        outFormat = .jpeg
                        outQuality = q
                        suffix = " small"
                        if keep { meta = ImageEngine.keptMetadata(item.data) }
                    case .resizeImage:
                        if byPct {
                            maxPixel = max(1, Int(Double(longest) * pct))
                        } else if let i = info {
                            let sw = tw.map { Double($0) / Double(max(1, i.pixelWidth)) } ?? .infinity
                            let sh = th.map { Double($0) / Double(max(1, i.pixelHeight)) } ?? .infinity
                            let s = min(sw, sh)
                            maxPixel = max(1, Int(Double(longest) * (s.isFinite ? s : 1)))
                        }
                        suffix = " resized"
                        if keep { meta = ImageEngine.keptMetadata(item.data) }
                    case .convertImage:
                        outFormat = fmt
                        outQuality = q
                        if keep { meta = ImageEngine.keptMetadata(item.data) }
                    default:
                        suffix = " clean"
                        outQuality = 0.95
                    }
                    // Upscaling isn't allowed by the thumbnail decoder past the original; resize can enlarge via redraw.
                    guard var cg = ImageEngine.decode(item.data, maxPixel: maxPixel.map { min($0, longest) }) else {
                        throw ToolError("Couldn't read \(item.name).")
                    }
                    if t == .resizeImage, let mp = maxPixel, mp > longest, longest > 0 {
                        let s = CGFloat(mp) / CGFloat(longest)
                        let size = CGSize(width: CGFloat(cg.width) * s, height: CGFloat(cg.height) * s)
                        let fmtR = UIGraphicsImageRendererFormat()
                        fmtR.scale = 1
                        let up = UIGraphicsImageRenderer(size: size, format: fmtR).image { _ in UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size)) }
                        if let c = up.cgImage { cg = c }
                    }
                    guard let data = ImageEngine.encode(cg, as: outFormat, quality: outQuality, metadata: meta) else {
                        throw ToolError("Couldn't save \(item.name) as \(outFormat.rawValue).")
                    }
                    before += item.data.count
                    after += data.count
                    files.append(try FileLibrary.shared.save(data, name: item.baseName + suffix + "." + outFormat.ext))
                }
                progress(Double(n + 1) / Double(items.count))
            }
            let b = ByteCountFormatter.string(fromByteCount: Int64(before), countStyle: .file)
            let a = ByteCountFormatter.string(fromByteCount: Int64(after), countStyle: .file)
            let msg: String
            switch t {
            case .compressImage: msg = "\(b) → \(a)" + (before > 0 ? " (\(max(0, Int((1 - Double(after) / Double(before)) * 100)))% smaller)." : ".")
            case .resizeImage: msg = "Resized \(files.count) image(s)."
            case .convertImage: msg = "Converted \(files.count) image(s) to \(fmt.rawValue)."
            default: msg = "Removed personal info from \(files.count) image(s)."
            }
            return ToolResult(files: files, message: msg, images: files.map(\.url))
        }
    }
}
