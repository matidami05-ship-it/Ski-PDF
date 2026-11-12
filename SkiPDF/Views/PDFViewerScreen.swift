import SwiftUI
import PDFKit

/// Full-screen PDF reader: thumbnails, search, page jump, highlight/underline/strike-out, notes,
/// form filling, then save back.
struct PDFViewerScreen: View {
    let url: URL
    /// Called with the saved file when edits are saved (nil = save over `url`).
    var saveAsNew: Bool = false
    var initialPassword: String? = nil

    @Environment(\.dismiss) var dismiss
    @StateObject private var model: PDFViewerModel

    init(url: URL, saveAsNew: Bool = false, initialPassword: String? = nil) {
        self.url = url
        self.saveAsNew = saveAsNew
        self.initialPassword = initialPassword
        // Load right away so the first frame already has the document.
        _model = StateObject(wrappedValue: PDFViewerModel(url: url, password: initialPassword))
    }
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showGoTo = false
    @State private var goToText = ""
    @State private var showNote = false
    @State private var noteText = ""
    @State private var password = ""
    @State private var showPrint = false

    var body: some View {
        NavigationStack {
            ZStack {
                if let doc = model.document, !doc.isLocked {
                    VStack(spacing: 0) {
                        PDFKitView(model: model)
                            .ignoresSafeArea(edges: model.immersive ? .all : [])
                        if model.showThumbnails && !model.immersive {
                            ThumbnailStrip(model: model).frame(height: 76)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                } else if model.document?.isLocked == true {
                    VStack(spacing: 14) {
                        Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                        Text("This PDF is password-protected").font(.headline)
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
                            .onSubmit { _ = model.unlock(password) }
                        Button("Unlock") { _ = model.unlock(password) }.buttonStyle(.borderedProminent)
                        if model.wrongPassword { Text("Wrong password").foregroundStyle(Theme.danger).font(.footnote) }
                    }
                } else if model.failed {
                    ContentUnavailableView("Can't open this PDF", systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView()
                }
            }
            .toolBackground()
            // Zoomed in: hide every bar so the page fills the screen. Zoom back out (or tap) to bring them back.
            .toolbar(model.immersive ? .hidden : .visible, for: .navigationBar)
            .toolbar(model.immersive ? .hidden : .visible, for: .bottomBar)
            .statusBarHidden(model.immersive)
            .animation(.easeInOut(duration: 0.22), value: model.immersive)
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if model.dirty { model.askSave = true } else { dismiss() }
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showSearch.toggle() } label: { Image(systemName: "magnifyingglass") }
                    Menu {
                        Button { showGoTo = true } label: { Label("Go to page…", systemImage: "number") }
                        Button { model.showThumbnails.toggle() } label: { Label(model.showThumbnails ? "Hide thumbnails" : "Show thumbnails", systemImage: "rectangle.grid.1x2") }
                        Picker("Layout", selection: $model.layout) {
                            ForEach(PDFViewerModel.Layout.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                        }
                        Divider()
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                        Button { model.print() } label: { Label("Print", systemImage: "printer") }
                        if model.dirty {
                            Button { model.save(to: url, asNew: saveAsNew) } label: { Label("Save changes", systemImage: "square.and.arrow.down") }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { model.markup(.highlight) } label: { Image(systemName: "highlighter") }
                        .accessibilityLabel("Highlight")
                    Button { model.markup(.underline) } label: { Image(systemName: "underline") }
                    Button { model.markup(.strikeOut) } label: { Image(systemName: "strikethrough") }
                    Button { noteText = ""; showNote = true } label: { Image(systemName: "note.text.badge.plus") }
                        .accessibilityLabel("Add note")
                    Button { model.removeMarkupUnderSelection() } label: { Image(systemName: "eraser") }
                        .accessibilityLabel("Remove markup")
                    Spacer()
                    Text(model.pageLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    if model.dirty {
                        Button("Save") { model.save(to: url, asNew: saveAsNew) }.fontWeight(.semibold)
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if showSearch && !model.immersive {
                    HStack {
                        TextField("Search in PDF", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.search)
                            .onSubmit { model.search(searchText) }
                        if !model.matches.isEmpty {
                            Text("\(model.matchIndex + 1)/\(model.matches.count)").font(.caption.monospacedDigit())
                            Button { model.nextMatch(-1) } label: { Image(systemName: "chevron.up") }
                            Button { model.nextMatch(1) } label: { Image(systemName: "chevron.down") }
                        } else if model.searched {
                            Text("No results").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(.bar)
                }
            }
            .alert("Go to page", isPresented: $showGoTo) {
                TextField("Page number", text: $goToText).keyboardType(.numberPad)
                Button("Go") { if let n = Int(goToText) { model.go(to: n - 1) } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Add note", isPresented: $showNote) {
                TextField("Note", text: $noteText)
                Button("Add") { model.addNote(noteText) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("The note is placed on the page you're viewing.") }
            .alert("Save changes?", isPresented: $model.askSave) {
                Button("Save") { model.save(to: url, asNew: saveAsNew); dismiss() }
                Button("Discard", role: .destructive) { dismiss() }
                Button("Cancel", role: .cancel) {}
            }
            .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

@MainActor
final class PDFViewerModel: ObservableObject {
    enum Layout: String, CaseIterable, Identifiable {
        case scroll = "Continuous", single = "Single page", twoUp = "Two pages"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .scroll: return "rectangle.split.1x2"
            case .single: return "doc"
            case .twoUp: return "book"
            }
        }
    }

    @Published var document: PDFDocument?
    @Published var failed = false
    @Published var wrongPassword = false
    @Published var title = ""
    @Published var pageLabel = ""
    @Published var dirty = false
    @Published var askSave = false
    @Published var message: String?
    @Published var showThumbnails = true
    @Published var layout: Layout = .scroll { didSet { applyLayout() } }
    @Published var matches: [PDFSelection] = []
    @Published var matchIndex = 0
    @Published var searched = false
    /// True while zoomed in past fit-to-width: bars are hidden.
    @Published var immersive = false

    /// One PDF view for the screen, shared by the page view and the thumbnail strip.
    let pdfView: SizingPDFView = {
        let v = SizingPDFView()
        v.backgroundColor = UIColor(Theme.background)
        v.pageShadowsEnabled = true
        v.displayDirection = .vertical
        return v
    }()

    init(url: URL, password: String?) {
        load(url, password: password)
    }
    private var password: String?
    private var observers: [NSObjectProtocol] = []

    func load(_ url: URL, password: String?) {
        guard document == nil else { return }
        title = url.deletingPathExtension().lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // Read the bytes first: PDFDocument(url:) can fail silently on some file locations.
        guard let data = try? Data(contentsOf: url), let d = PDFDocument(data: data) ?? PDFDocument(url: url) else { failed = true; return }
        if d.isLocked, let pw = password { _ = d.unlock(withPassword: pw); self.password = pw }
        document = d
        if !d.isLocked { pdfView.document = d }
        observers.append(NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updatePageLabel() }
        })
        // Typing in form fields counts as an edit.
        observers.append(NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: pdfView, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.zoomChanged() }
        })
        pdfView.onTap = { [weak self] in
            Task { @MainActor in self?.tapped() }
        }
        observers.append(NotificationCenter.default.addObserver(forName: .PDFViewAnnotationHit, object: pdfView, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dirty = true }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dirty = true }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UITextView.textDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dirty = true }
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func unlock(_ pw: String) -> Bool {
        guard let d = document else { return false }
        if d.unlock(withPassword: pw) {
            password = pw
            wrongPassword = false
            pdfView.document = d
            pdfView.fitToWidth()
            objectWillChange.send()
            return true
        }
        wrongPassword = true
        return false
    }

    private var lastZoomed = false

    func zoomChanged() {
        let zoomed = pdfView.isZoomedIn
        guard zoomed != lastZoomed else { return }
        lastZoomed = zoomed
        if immersive != zoomed { immersive = zoomed }
    }

    /// A tap while zoomed in shows or hides the bars without changing the zoom.
    func tapped() {
        guard pdfView.isZoomedIn else { return }
        immersive.toggle()
    }

    func attach() {
        applyLayout()
        updatePageLabel()
    }

    func applyLayout() {
        let v = pdfView
        switch layout {
        case .scroll: v.displayMode = .singlePageContinuous; v.displaysAsBook = false
        case .single: v.displayMode = .singlePage; v.displaysAsBook = false
        case .twoUp: v.displayMode = .twoUpContinuous; v.displaysAsBook = true
        }
        v.fitToWidth()
    }

    func updatePageLabel() {
        guard let d = document, let p = pdfView.currentPage else { return }
        pageLabel = "\(d.index(for: p) + 1) / \(d.pageCount)"
    }

    func go(to index: Int) {
        guard let d = document, let p = d.page(at: max(0, min(d.pageCount - 1, index))) else { return }
        pdfView.go(to: p)
    }

    func search(_ text: String) {
        guard let d = document else { return }
        let q = text.trimmingCharacters(in: .whitespaces)
        searched = !q.isEmpty
        matches = q.isEmpty ? [] : d.findString(q, withOptions: [.caseInsensitive, .diacriticInsensitive])
        matchIndex = 0
        for m in matches { m.color = UIColor.systemYellow.withAlphaComponent(0.5) }
        pdfView.highlightedSelections = matches
        if let first = matches.first { show(first) }
    }

    func nextMatch(_ step: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + step + matches.count) % matches.count
        show(matches[matchIndex])
    }

    private func show(_ s: PDFSelection) {
        pdfView.setCurrentSelection(s, animate: true)
        pdfView.go(to: s)
    }

    func markup(_ type: PDFAnnotationSubtype) {
        guard let sel = pdfView.currentSelection, !(sel.string ?? "").isEmpty else {
            message = "Select some text first (press and hold on a word, then drag the handles)."
            return
        }
        for line in sel.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                let a = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
                switch type {
                case .highlight: a.color = UIColor.systemYellow.withAlphaComponent(0.55)
                case .underline: a.color = .systemBlue
                default: a.color = .systemRed
                }
                page.addAnnotation(a)
            }
        }
        pdfView.clearSelection()
        dirty = true
    }

    func removeMarkupUnderSelection() {
        let v = pdfView
        let kinds: Set<String> = ["Highlight", "Underline", "StrikeOut", "Text", "FreeText"]
        var removed = 0
        if let sel = v.currentSelection {
            for page in sel.pages {
                let b = sel.bounds(for: page)
                for a in page.annotations where kinds.contains(a.type ?? "") && a.bounds.intersects(b) {
                    page.removeAnnotation(a); removed += 1
                }
            }
            v.clearSelection()
        }
        if removed == 0 { message = "Select the marked-up text first, then tap the eraser." } else { dirty = true }
    }

    func addNote(_ text: String) {
        let v = pdfView
        guard let page = v.currentPage, !text.isEmpty else { return }
        let pb = page.bounds(for: .cropBox)
        // Place it near the middle of what's on screen.
        let center = v.convert(CGPoint(x: v.bounds.midX, y: v.bounds.midY), to: page)
        let size = CGSize(width: min(220, pb.width * 0.6), height: 60)
        var rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        rect.origin.x = max(pb.minX + 8, min(rect.origin.x, pb.maxX - size.width - 8))
        rect.origin.y = max(pb.minY + 8, min(rect.origin.y, pb.maxY - size.height - 8))
        let a = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
        a.contents = text
        a.font = UIFont.systemFont(ofSize: 12)
        a.fontColor = .black
        a.color = UIColor(red: 1, green: 0.96, blue: 0.7, alpha: 0.95)
        let border = PDFBorder()
        border.lineWidth = 0.5
        a.border = border
        page.addAnnotation(a)
        dirty = true
    }

    func save(to url: URL, asNew: Bool) {
        guard let d = document else { return }
        let target = asNew ? FileLibrary.shared.uniqueURL(url.deletingPathExtension().lastPathComponent + " edited.pdf") : url
        var opts: [PDFDocumentWriteOption: Any] = [:]
        if d.isEncrypted, let pw = password {
            opts[.userPasswordOption] = pw
            opts[.ownerPasswordOption] = pw
        }
        let tmp = Scratch.url(target.lastPathComponent)
        let ok = opts.isEmpty ? d.write(to: tmp) : d.write(to: tmp, withOptions: opts)
        guard ok else { message = "Couldn't save the PDF."; return }
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: target)
            }
            dirty = false
            FileLibrary.shared.refresh()
            if asNew { message = "Saved as \"\(target.lastPathComponent)\" in Files." }
        } catch {
            message = "Couldn't save: \(error.localizedDescription)"
        }
    }

    func print() {
        guard let data = document?.dataRepresentation() else { return }
        let pc = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = title
        info.outputType = .general
        pc.printInfo = info
        pc.printingItem = data
        pc.present(animated: true)
    }
}

struct PDFKitView: UIViewRepresentable {
    @ObservedObject var model: PDFViewerModel

    func makeUIView(context: Context) -> SizingPDFView {
        let v = model.pdfView
        if v.document == nil, let d = model.document, !d.isLocked { v.document = d }
        model.attach()
        return v
    }

    func updateUIView(_ v: SizingPDFView, context: Context) {
        if let d = model.document, !d.isLocked, v.document !== d { v.document = d; v.fitToWidth() }
    }
}

/// A PDFView that re-fits the page whenever it gets a real size (PDFKit can't fit a zero-sized view,
/// which otherwise leaves the pages invisible).
final class SizingPDFView: PDFView {
    private var lastSize: CGSize = .zero
    /// The scale that fits the page width at the current size.
    private(set) var fitScale: CGFloat = 0
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = SimultaneousTapDelegate.shared
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    /// Zoomed in noticeably past fit-to-width.
    var isZoomedIn: Bool { fitScale > 0 && scaleFactor > fitScale * 1.08 }

    override func layoutSubviews() {
        let wasZoomed = isZoomedIn
        super.layoutSubviews()
        guard bounds.width > 1, bounds.height > 1, bounds.size != lastSize else { return }
        lastSize = bounds.size
        if wasZoomed {
            // Bars hid or showed while zoomed in: keep the zoom, just update what "fit" means.
            updateFitScale()
        } else {
            fitToWidth() // first layout, rotation, bars coming back after zooming out
        }
    }

    private func updateFitScale() {
        autoScales = true
        let fit = scaleFactorForSizeToFit
        autoScales = false
        if fit > 0 {
            fitScale = fit
            minScaleFactor = fit * 0.5
            maxScaleFactor = max(fit * 8, 4)
        }
    }

    func fitToWidth() {
        guard document != nil, bounds.width > 1 else { return }
        updateFitScale()
        if fitScale > 0 { scaleFactor = fitScale }
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        // Ignore taps on links and form fields.
        let p = g.location(in: self)
        if let page = page(for: p, nearest: false), page.annotation(at: convert(p, to: page)) != nil { return }
        onTap?()
    }
}

/// Lets the "show/hide bars" tap work alongside PDFKit's own gestures.
private final class SimultaneousTapDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SimultaneousTapDelegate()
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

struct ThumbnailStrip: UIViewRepresentable {
    @ObservedObject var model: PDFViewerModel
    func makeUIView(context: Context) -> PDFThumbnailView {
        let t = PDFThumbnailView()
        t.layoutMode = .horizontal
        t.thumbnailSize = CGSize(width: 44, height: 60)
        t.backgroundColor = UIColor(Theme.background).withAlphaComponent(0.95)
        t.pdfView = model.pdfView
        return t
    }
    func updateUIView(_ t: PDFThumbnailView, context: Context) {}
}

/// View PDF tool: pick any PDF and open it in the reader.
struct ViewPDFTool: View {
    @State private var pdf: PickedPDF?
    @State private var opened: PickedPDF?
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Read, search, highlight and add notes. Form fields can be typed into directly.")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                PDFPicker(allowLocked: true) { picked in
                    pdf = picked.first
                    opened = picked.first
                }
            }
            .padding(16)
        }
        .toolBackground()
        .fullScreenCover(item: $opened) { p in
            PDFViewerScreen(url: p.url, saveAsNew: true, initialPassword: p.password)
        }
    }
}
