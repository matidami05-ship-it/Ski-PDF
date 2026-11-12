import SwiftUI
import PDFKit

// MARK: - Lock

struct LockTool: View {
    @StateObject private var runner = ToolRunner()
    @State private var pdf: PickedPDF?
    @State private var password = ""
    @State private var confirm = ""
    @State private var printing = true
    @State private var copying = true
    @State private var show = false

    private var problem: String? {
        if password.count < 4 { return "Use at least 4 characters." }
        if password != confirm { return "The passwords don't match." }
        return nil
    }

    var body: some View {
        SinglePDFToolLayout(pdf: $pdf, actionTitle: "Lock PDF", actionSymbol: "lock.fill", actionDisabled: problem != nil, busy: runner.busy,
                            hint: "Anyone opening the PDF will need this password.", action: run) {
            Panel(title: "Password") {
                Group {
                    if show {
                        TextField("Password", text: $password)
                        TextField("Type it again", text: $confirm)
                    } else {
                        SecureField("Password", text: $password)
                        SecureField("Type it again", text: $confirm)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Toggle("Show password", isOn: $show)
                if let p = problem, !password.isEmpty { Text(p).font(.footnote).foregroundStyle(Theme.danger) }
                Text("Write it down — there's no way to recover it.").font(.footnote).foregroundStyle(.secondary)
            }
            Panel(title: "After opening, allow") {
                Toggle("Printing", isOn: $printing)
                Toggle("Copying text", isOn: $copying)
            }
        }
        .toolRunner(runner)
    }

    private func run() {
        guard let p = pdf else { return }
        let doc = p.document, name = p.name, pw = password, pr = printing, cp = copying
        runner.run { _ in
            let tmp = try PDFEngine.locked(doc, userPassword: pw, ownerPassword: nil, allowPrinting: pr, allowCopying: cp)
            let f = try FileLibrary.shared.adopt(tmp, name: "\(name) locked.pdf")
            return ToolResult(files: [f], message: "Locked. It now asks for the password when opened.")
        }
    }
}

// MARK: - Unlock

struct UnlockTool: View {
    @StateObject private var runner = ToolRunner()
    @State private var pdf: PickedPDF?
    @State private var password = ""
    @State private var wrong = false

    var body: some View {
        SinglePDFToolLayout(pdf: $pdf, allowLocked: true, actionTitle: "Remove Password", actionSymbol: "lock.open.fill",
                            actionDisabled: (pdf?.isLocked ?? false) && password.isEmpty, busy: runner.busy,
                            hint: "You need to know the current password.", action: run) {
            if let p = pdf {
                if p.isLocked {
                    Panel(title: "Current password") {
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(run)
                        if wrong { Text("That password didn't work.").font(.footnote).foregroundStyle(Theme.danger) }
                    }
                } else if p.document.isEncrypted {
                    Text("This PDF opens without a password but has restrictions (like no printing or copying). Removing them makes a fully open copy.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("This PDF isn't protected. You can still save an open copy.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .toolRunner(runner)
    }

    private func run() {
        guard let p = pdf else { return }
        if p.isLocked {
            guard p.unlock(password) else { wrong = true; return }
        }
        wrong = false
        let doc = p.document, name = p.name
        runner.run { _ in
            let open = try PDFEngine.unlocked(doc)
            let f = try PDFEngine.save(open, name: "\(name) unlocked")
            return ToolResult(files: [f], message: "Password removed. The copy opens without one.")
        }
    }
}

// MARK: - Watermark

struct WatermarkTool: View {
    @StateObject private var runner = ToolRunner()
    @State private var pdf: PickedPDF?
    @State private var text = "CONFIDENTIAL"
    @State private var size = 60.0
    @State private var color = Color.red
    @State private var opacity = 0.25
    @State private var angle = 45.0
    @State private var tiled = false
    @State private var bold = true
    @State private var pages = ""
    @State private var preview: UIImage?

    private var style: PDFEngine.WatermarkStyle {
        PDFEngine.WatermarkStyle(text: text, fontSize: CGFloat(size), color: UIColor(color), opacity: CGFloat(opacity),
                                 angle: CGFloat(angle), tiled: tiled, bold: bold)
    }

    var body: some View {
        SinglePDFToolLayout(pdf: $pdf, actionTitle: "Add Watermark", actionSymbol: "drop.fill",
                            actionDisabled: text.trimmingCharacters(in: .whitespaces).isEmpty, busy: runner.busy, action: run) {
            if let preview {
                Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 260)
                    .shadow(radius: 4)
            }
            Panel(title: "Text") {
                TextField("Watermark text", text: $text).textFieldStyle(.roundedBorder)
                HStack {
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                    Toggle("Bold", isOn: $bold)
                }
                labeled("Size \(Int(size))") { Slider(value: $size, in: 12...160) }
                labeled("Opacity \(Int(opacity * 100))%") { Slider(value: $opacity, in: 0.05...1) }
                labeled("Angle \(Int(angle))°") { Slider(value: $angle, in: -90...90, step: 5) }
                Toggle("Repeat across the page", isOn: $tiled)
            }
            Panel(title: "Pages") {
                TextField("All pages (or e.g. 1-3)", text: $pages).textFieldStyle(.roundedBorder).keyboardType(.numbersAndPunctuation)
            }
        }
        .onChange(of: pdf?.id) { _, _ in updatePreview() }
        .onChange(of: text) { _, _ in updatePreview() }
        .onChange(of: size) { _, _ in updatePreview() }
        .onChange(of: color) { _, _ in updatePreview() }
        .onChange(of: opacity) { _, _ in updatePreview() }
        .onChange(of: angle) { _, _ in updatePreview() }
        .onChange(of: tiled) { _, _ in updatePreview() }
        .onChange(of: bold) { _, _ in updatePreview() }
        .toolRunner(runner)
    }

    private func labeled<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(t).font(.footnote); c() }
    }

    private func updatePreview() {
        guard let page = pdf?.document.page(at: 0) else { preview = nil; return }
        let s = style
        let size = PDFEngine.displaySize(page)
        let scale = 300 / max(size.width, size.height)
        preview = UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: ctx.format.bounds.size))
            ctx.cgContext.scaleBy(x: scale, y: scale)
            PDFEngine.drawPage(page, in: CGRect(origin: .zero, size: size), context: ctx.cgContext)
            PDFEngine.drawWatermark(s, size: size, cg: ctx.cgContext)
        }
    }

    private func run() {
        guard let p = pdf else { return }
        guard let list = PageRange.parse(pages, count: p.pageCount) else { runner.error = "Check the page numbers."; return }
        let doc = p.document, name = p.name, s = style, targets = Set(list)
        runner.run { progress in
            let data = PDFEngine.redraw(doc, progress: progress) { i, size, cg in
                if targets.contains(i) { PDFEngine.drawWatermark(s, size: size, cg: cg) }
            }
            let f = try PDFEngine.save(data, name: "\(name) watermarked")
            return ToolResult(files: [f], message: "Watermark added to \(targets.count) page(s).")
        }
    }
}

// MARK: - Sign

/// An image placed on a page (signature, initials). Drawn by PDFKit, so it shows in the viewer and
/// is baked into the page when the PDF is flattened on save.
final class ImageStampAnnotation: PDFAnnotation {
    let image: UIImage

    init(image: UIImage, bounds: CGRect) {
        self.image = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let cg = image.cgImage else { return }
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(cg, in: bounds)
        context.restoreGState()
    }
}

enum SignatureStore {
    static var folder: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Signatures", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func all() -> [URL] {
        let list = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return list.filter { $0.pathExtension == "png" }.sorted {
            ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) >
            ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        }
    }

    static func add(_ img: UIImage) {
        guard let d = img.pngData() else { return }
        try? d.write(to: folder.appendingPathComponent(UUID().uuidString + ".png"))
    }

    static func remove(_ u: URL) { try? FileManager.default.removeItem(at: u) }
}

struct SignTool: View {
    @StateObject private var runner = ToolRunner()
    @StateObject private var placer = StampPlacer()
    @State private var pdf: PickedPDF?
    @State private var signatures: [URL] = SignatureStore.all()
    @State private var showPad = false

    var body: some View {
        Group {
            if let p = pdf {
                VStack(spacing: 0) {
                    StampPDFView(document: p.document, placer: placer)
                    controls
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { save(p) }.fontWeight(.semibold).disabled(placer.count == 0 || runner.busy)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Draw or type your signature, place it on the page, then save.")
                            .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        PDFPicker { pdf = $0.first }
                    }.padding(16)
                }
            }
        }
        .toolBackground()
        .sheet(isPresented: $showPad) {
            SignaturePad { img in
                SignatureStore.add(img)
                signatures = SignatureStore.all()
                placer.add(img)
            }
        }
        .toolRunner(runner)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button { showPad = true } label: {
                        VStack { Image(systemName: "plus").font(.title3); Text("New").font(.caption) }
                            .frame(width: 88, height: 54)
                            .background(Theme.iconTile, in: RoundedRectangle(cornerRadius: 10))
                    }
                    ForEach(signatures, id: \.self) { u in
                        if let img = UIImage(contentsOfFile: u.path) {
                            Button { placer.add(img) } label: {
                                Image(uiImage: img).resizable().scaledToFit().padding(6)
                                    .frame(width: 120, height: 54)
                                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .contextMenu {
                                Button(role: .destructive) { SignatureStore.remove(u); signatures = SignatureStore.all() } label: { Label("Delete signature", systemImage: "trash") }
                            }
                        }
                    }
                    Button { placer.addDate() } label: {
                        VStack { Image(systemName: "calendar").font(.title3); Text("Date").font(.caption) }
                            .frame(width: 70, height: 54)
                            .background(Theme.iconTile, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 16)
            }
            if placer.hasSelection {
                HStack(spacing: 12) {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: Binding(get: { placer.scale }, set: { placer.setScale($0) }), in: 0.3...3)
                    Image(systemName: "plus.magnifyingglass")
                    Button(role: .destructive) { placer.deleteSelected() } label: { Image(systemName: "trash") }
                }
                .padding(.horizontal, 16)
                Text("Drag it with your finger to move it.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(placer.count == 0 ? "Tap a signature to place it on the page you're viewing." : "Tap a signature on the page to move or resize it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .background(Theme.background)
    }

    private func save(_ p: PickedPDF) {
        let doc = p.document, name = p.name
        runner.run { progress in
            let data = PDFEngine.redraw(doc, progress: progress)
            let f = try PDFEngine.save(data, name: "\(name) signed")
            return ToolResult(files: [f], message: "Signed and saved.")
        }
    }
}

/// Places, moves and resizes stamp annotations in a PDFView.
@MainActor
final class StampPlacer: NSObject, ObservableObject, UIGestureRecognizerDelegate {
    @Published var count = 0
    @Published var hasSelection = false
    @Published var scale: Double = 1

    weak var pdfView: PDFView?
    private var selected: PDFAnnotation?
    private var baseSize: [ObjectIdentifier: CGSize] = [:]
    private var dragOffset: CGPoint = .zero

    func attach(_ v: PDFView) {
        pdfView = v
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.delegate = self
        v.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        tap.delegate = self
        v.addGestureRecognizer(tap)
        // Scrolling waits until we know the finger isn't on a stamp.
        if let scroll = v.subviews.compactMap({ $0 as? UIScrollView }).first ?? v.subviews.flatMap(\.subviews).compactMap({ $0 as? UIScrollView }).first {
            scroll.panGestureRecognizer.require(toFail: pan)
        }
    }

    private func stamp(at point: CGPoint) -> (PDFAnnotation, PDFPage)? {
        guard let v = pdfView, let page = v.page(for: point, nearest: false) else { return nil }
        let p = v.convert(point, to: page)
        let hit = page.annotations.last { ($0 is ImageStampAnnotation || $0.userName == "ski-stamp") && $0.bounds.insetBy(dx: -12, dy: -12).contains(p) }
        return hit.map { ($0, page) }
    }

    nonisolated func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        MainActor.assumeIsolated {
            if g is UIPanGestureRecognizer { return stamp(at: g.location(in: pdfView)) != nil }
            return true
        }
    }

    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        g is UITapGestureRecognizer
    }

    @objc private func tap(_ g: UITapGestureRecognizer) {
        if let (a, _) = stamp(at: g.location(in: pdfView)) { select(a) } else { select(nil) }
    }

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        guard let v = pdfView else { return }
        let point = g.location(in: v)
        switch g.state {
        case .began:
            guard let (a, page) = stamp(at: point) else { return }
            select(a)
            let p = v.convert(point, to: page)
            dragOffset = CGPoint(x: p.x - a.bounds.minX, y: p.y - a.bounds.minY)
        case .changed:
            guard let a = selected, let page = a.page else { return }
            let p = v.convert(point, to: page)
            let pb = page.bounds(for: .cropBox)
            var r = a.bounds
            r.origin.x = max(pb.minX - r.width / 2, min(p.x - dragOffset.x, pb.maxX - r.width / 2))
            r.origin.y = max(pb.minY - r.height / 2, min(p.y - dragOffset.y, pb.maxY - r.height / 2))
            a.bounds = r
            v.annotationsChanged(on: page)
        default: break
        }
    }

    private func select(_ a: PDFAnnotation?) {
        selected = a
        hasSelection = a != nil
        if let a, let base = baseSize[ObjectIdentifier(a)] {
            scale = Double(a.bounds.width / max(1, base.width))
        }
    }

    /// Adds an image in the middle of the page on screen.
    func add(_ img: UIImage) {
        guard let v = pdfView, let page = v.currentPage else { return }
        let pb = page.bounds(for: .cropBox)
        let w = min(180, pb.width * 0.35)
        let h = w * img.size.height / max(1, img.size.width)
        let c = v.convert(CGPoint(x: v.bounds.midX, y: v.bounds.midY), to: page)
        let r = CGRect(x: min(max(pb.minX, c.x - w / 2), pb.maxX - w), y: min(max(pb.minY, c.y - h / 2), pb.maxY - h), width: w, height: h)
        let a = ImageStampAnnotation(image: img, bounds: r)
        a.userName = "ski-stamp"
        page.addAnnotation(a)
        baseSize[ObjectIdentifier(a)] = r.size
        count += 1
        select(a)
    }

    func addDate() {
        let s = Date().formatted(date: .numeric, time: .omitted)
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 48, weight: .medium), .foregroundColor: UIColor.black]
        let size = (s as NSString).size(withAttributes: attrs)
        let img = UIGraphicsImageRenderer(size: CGSize(width: size.width + 8, height: size.height + 4)).image { _ in
            (s as NSString).draw(at: CGPoint(x: 4, y: 2), withAttributes: attrs)
        }
        add(img)
    }

    func setScale(_ s: Double) {
        guard let a = selected, let base = baseSize[ObjectIdentifier(a)], let page = a.page else { return }
        scale = s
        let c = CGPoint(x: a.bounds.midX, y: a.bounds.midY)
        let w = base.width * CGFloat(s), h = base.height * CGFloat(s)
        a.bounds = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        pdfView?.annotationsChanged(on: page)
    }

    func deleteSelected() {
        guard let a = selected, let page = a.page else { return }
        page.removeAnnotation(a)
        count = max(0, count - 1)
        select(nil)
    }
}

struct StampPDFView: UIViewRepresentable {
    let document: PDFDocument
    let placer: StampPlacer

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = document
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = UIColor(Theme.background)
        DispatchQueue.main.async { placer.attach(v) }
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {}
}

/// Draw (finger or Apple Pencil) or type a signature.
struct SignaturePad: View {
    enum Mode: String, CaseIterable, Identifiable {
        case draw = "Draw", type = "Type"
        var id: String { rawValue }
    }

    let onDone: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var mode = Mode.draw
    @State private var typed = ""
    @State private var ink = Color.black
    @State private var canvas = SignatureCanvas.Model()
    @State private var font = "SnellRoundhand-Bold"

    private let fonts = ["SnellRoundhand-Bold", "Zapfino", "BradleyHandITCTT-Bold", "SavoyeLetPlain", "Noteworthy-Bold"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Mode", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color.white)
                    if mode == .draw {
                        SignatureCanvas(model: canvas, color: UIColor(ink))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        VStack {
                            Spacer()
                            Rectangle().fill(Color.gray.opacity(0.5)).frame(height: 1).padding(.horizontal, 24).padding(.bottom, 44)
                        }
                        .allowsHitTesting(false)
                    } else {
                        Text(typed.isEmpty ? "Your name" : typed)
                            .font(.custom(font, size: 44))
                            .foregroundStyle(typed.isEmpty ? Color.gray.opacity(0.4) : ink)
                            .minimumScaleFactor(0.3)
                            .lineLimit(1)
                            .padding()
                    }
                }
                .frame(height: 220)
                if mode == .type {
                    TextField("Type your name", text: $typed).textFieldStyle(.roundedBorder)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(fonts, id: \.self) { f in
                                Button { font = f } label: {
                                    Text(typed.isEmpty ? "Signature" : typed).font(.custom(f, size: 22))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(font == f ? Theme.accent : .clear, lineWidth: 3))
                                }
                            }
                        }
                    }
                }
                HStack {
                    ForEach([Color.black, Color(red: 0.05, green: 0.2, blue: 0.6), Color(red: 0.1, green: 0.35, blue: 0.2)], id: \.self) { c in
                        Circle().fill(c).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(ink == c ? Theme.accent : .clear, lineWidth: 3).padding(-4))
                            .onTapGesture { ink = c }
                    }
                    Spacer()
                    if mode == .draw { Button("Clear") { canvas.clear() } }
                }
                Spacer()
            }
            .padding(16)
            .toolBackground()
            .navigationTitle("Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        if let img = makeImage() { onDone(img) }
                        dismiss()
                    }
                }
            }
        }
    }

    private func makeImage() -> UIImage? {
        if mode == .draw { return canvas.image() }
        let t = typed.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let uiFont = UIFont(name: font, size: 120) ?? UIFont.italicSystemFont(ofSize: 120)
        let attrs: [NSAttributedString.Key: Any] = [.font: uiFont, .foregroundColor: UIColor(ink)]
        let size = (t as NSString).size(withAttributes: attrs)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: ceil(size.width) + 20, height: ceil(size.height) + 10), format: format).image { _ in
            (t as NSString).draw(at: CGPoint(x: 10, y: 5), withAttributes: attrs)
        }
    }
}

// MARK: - Fill forms

struct FillFormsTool: View {
    @StateObject private var runner = ToolRunner()
    @State private var pdf: PickedPDF?
    @State private var flatten = false
    @State private var fieldCount = 0

    var body: some View {
        Group {
            if let p = pdf {
                VStack(spacing: 0) {
                    if fieldCount == 0 {
                        Text("This PDF has no fillable fields. You can still add text with View PDF › note.")
                            .font(.footnote).foregroundStyle(.secondary).padding(10)
                    } else {
                        Text("Tap a field to type. \(fieldCount) field\(fieldCount == 1 ? "" : "s") found.")
                            .font(.footnote).foregroundStyle(.secondary).padding(8)
                    }
                    FormPDFView(document: p.document)
                    HStack {
                        Toggle("Flatten (lock answers in)", isOn: $flatten).font(.subheadline)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { save(p) }.fontWeight(.semibold).disabled(runner.busy)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Open a PDF form, type into its fields and tick its boxes, then save a filled copy.")
                            .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        PDFPicker { picked in
                            pdf = picked.first
                            if let d = pdf?.document {
                                fieldCount = (0..<d.pageCount).reduce(0) { n, i in
                                    n + (d.page(at: i)?.annotations.filter { $0.type == "Widget" }.count ?? 0)
                                }
                            }
                        }
                    }.padding(16)
                }
            }
        }
        .toolBackground()
        .toolRunner(runner)
    }

    private func save(_ p: PickedPDF) {
        // Commit the field being typed in.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let doc = p.document, name = p.name, flat = flatten
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            runner.run { progress in
                if flat {
                    let f = try PDFEngine.save(PDFEngine.redraw(doc, progress: progress), name: "\(name) filled")
                    return ToolResult(files: [f], message: "Form filled and flattened.")
                }
                let f = try PDFEngine.save(doc, name: "\(name) filled")
                return ToolResult(files: [f], message: "Form saved. The fields can still be edited.")
            }
        }
    }
}

struct FormPDFView: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.document = document
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = UIColor(Theme.background)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}

// MARK: - Flatten

struct FlattenTool: View {
    enum Mode: String, CaseIterable, Identifiable {
        case vector = "Keep text sharp", image = "As images"
        var id: String { rawValue }
    }

    @StateObject private var runner = ToolRunner()
    @State private var pdf: PickedPDF?
    @State private var mode = Mode.vector

    var body: some View {
        SinglePDFToolLayout(pdf: $pdf, actionTitle: "Flatten", actionSymbol: "square.3.layers.3d.down.right", busy: runner.busy,
                            hint: "Turns form fields, highlights, notes and stamps into a permanent part of the page, so they can't be edited or removed.",
                            action: run) {
            Panel(title: "Method") {
                Picker("Method", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                Text(mode == .vector ? "Text stays selectable and crisp." : "Every page becomes a picture (200 dpi). Nothing can be copied or edited.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .toolRunner(runner)
    }

    private func run() {
        guard let p = pdf else { return }
        let doc = p.document, name = p.name, m = mode
        runner.run { progress in
            let data = m == .vector ? PDFEngine.redraw(doc, progress: progress)
                                    : PDFEngine.rasterized(doc, dpi: 200, quality: 0.85, grayscale: false, progress: progress)
            let f = try PDFEngine.save(data, name: "\(name) flattened")
            return ToolResult(files: [f], message: "Flattened \(doc.pageCount) page(s).")
        }
    }
}
