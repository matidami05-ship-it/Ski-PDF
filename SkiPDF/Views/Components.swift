import SwiftUI
import PDFKit
import QuickLook
import UniformTypeIdentifiers
import PhotosUI

// MARK: - Picked inputs

/// A PDF chosen as a tool's input (copied into scratch space so it can be read freely).
final class PickedPDF: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let name: String
    let document: PDFDocument
    /// Password used to open it, if it was locked.
    var password: String?

    init?(url: URL, name: String? = nil) {
        guard let doc = PDFDocument(url: url) else { return nil }
        self.url = url
        self.name = name ?? url.deletingPathExtension().lastPathComponent
        self.document = doc
    }

    var isLocked: Bool { document.isLocked }
    var pageCount: Int { document.pageCount }

    func unlock(_ pw: String) -> Bool {
        if document.unlock(withPassword: pw) { password = pw; return true }
        return false
    }
}

/// Where a file can be picked from.
enum PickSource { case files, library, photos }

/// "Choose PDF" button with a menu for the Files app or Ski PDF's own files. Handles locked PDFs.
struct PDFPicker: View {
    var title: String = "Choose PDF"
    var multiple: Bool = false
    var allowLocked: Bool = false
    let onPick: ([PickedPDF]) -> Void

    @State private var showImporter = false
    @State private var showLibrary = false
    @State private var lockedQueue: [PickedPDF] = []
    @State private var ready: [PickedPDF] = []
    @State private var password = ""
    @State private var wrongPassword = false
    @State private var error: String?

    var body: some View {
        Menu {
            Button { showImporter = true } label: { Label("Files app", systemImage: "folder") }
            Button { showLibrary = true } label: { Label("Ski PDF files", systemImage: "tray.full") }
        } label: {
            Label(title, systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.iconTile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(Theme.accent)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: multiple) { result in
            if case .success(let urls) = result { load(urls) }
        }
        .sheet(isPresented: $showLibrary) {
            LibraryPicker(filter: { $0.isPDF }, multiple: multiple) { files in load(files.map(\.url)) }
        }
        .alert("Password needed", isPresented: Binding(get: { !lockedQueue.isEmpty }, set: { if !$0 { lockedQueue.removeAll() } })) {
            SecureField("Password", text: $password)
            Button("Open") { tryUnlock() }
            Button("Skip", role: .cancel) { skipLocked() }
        } message: {
            Text(wrongPassword ? "That password didn't work. Try again." : "\"\(lockedQueue.first?.name ?? "This PDF")\" is protected with a password.")
        }
        .alert("Couldn't open", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func load(_ urls: [URL]) {
        var opened: [PickedPDF] = []
        var locked: [PickedPDF] = []
        var failed: [String] = []
        for u in urls {
            guard let local = try? Scratch.copyIn(u), let p = PickedPDF(url: local, name: u.deletingPathExtension().lastPathComponent) else {
                failed.append(u.lastPathComponent)
                continue
            }
            if p.isLocked && !allowLocked { locked.append(p) } else { opened.append(p) }
        }
        if !failed.isEmpty { error = "These aren't readable PDFs: " + failed.joined(separator: ", ") }
        ready = opened
        password = ""
        wrongPassword = false
        if locked.isEmpty { finish() } else { lockedQueue = locked }
    }

    private func tryUnlock() {
        guard let p = lockedQueue.first else { return }
        if p.unlock(password) {
            ready.append(p)
            lockedQueue.removeFirst()
            wrongPassword = false
        } else {
            wrongPassword = true
            // Re-show the alert for the same file.
            let q = lockedQueue
            lockedQueue = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { lockedQueue = q }
        }
        password = ""
        if lockedQueue.isEmpty && !wrongPassword { finish() }
    }

    private func skipLocked() {
        if !lockedQueue.isEmpty { lockedQueue.removeFirst() }
        if lockedQueue.isEmpty { finish() }
    }

    private func finish() {
        if !ready.isEmpty { onPick(ready) }
        ready = []
    }
}

/// Lets the user pick files already saved in Ski PDF.
struct LibraryPicker: View {
    let filter: (LibraryFile) -> Bool
    var multiple: Bool = false
    let onPick: ([LibraryFile]) -> Void

    @EnvironmentObject var library: FileLibrary
    @Environment(\.dismiss) var dismiss
    @State private var chosen = Set<URL>()

    var body: some View {
        NavigationStack {
            let items = library.files.filter(filter)
            Group {
                if items.isEmpty {
                    ContentUnavailableView("Nothing here yet", systemImage: "tray", description: Text("Files you make or import with Ski PDF show up here."))
                } else {
                    List(items) { f in
                        Button {
                            if multiple {
                                if chosen.contains(f.url) { chosen.remove(f.url) } else { chosen.insert(f.url) }
                            } else {
                                dismiss()
                                onPick([f])
                            }
                        } label: {
                            HStack {
                                FileRow(file: f)
                                if multiple {
                                    Image(systemName: chosen.contains(f.url) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(chosen.contains(f.url) ? Theme.accent : .secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Ski PDF files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if multiple {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add \(chosen.count)") {
                            let picked = items.filter { chosen.contains($0.url) }
                            dismiss()
                            onPick(picked)
                        }.disabled(chosen.isEmpty)
                    }
                }
            }
        }
    }
}

/// Picks images from Photos, the Files app or Ski PDF's files, as (data, name) pairs.
struct ImagePicker: View {
    var title: String = "Add Images"
    var multiple: Bool = true
    let onPick: ([PickedImage]) -> Void

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showImporter = false
    @State private var showLibrary = false
    @State private var loading = false

    var body: some View {
        Menu {
            Button { showPhotos = true } label: { Label("Photos", systemImage: "photo.on.rectangle") }
            Button { showImporter = true } label: { Label("Files app", systemImage: "folder") }
            Button { showLibrary = true } label: { Label("Ski PDF files", systemImage: "tray.full") }
        } label: {
            HStack {
                if loading { ProgressView() } else { Image(systemName: "plus.circle.fill") }
                Text(loading ? "Loading…" : title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.iconTile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Theme.accent)
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: multiple ? 200 : 1, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            loading = true
            Task {
                var out: [PickedImage] = []
                for (i, item) in items.enumerated() {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                        out.append(PickedImage(data: data, name: "Photo \(i + 1).\(ext)"))
                    }
                }
                await MainActor.run {
                    loading = false
                    photoItems = []
                    if !out.isEmpty { onPick(out) }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image], allowsMultipleSelection: multiple) { result in
            guard case .success(let urls) = result else { return }
            let out = urls.compactMap { u -> PickedImage? in
                let scoped = u.startAccessingSecurityScopedResource()
                defer { if scoped { u.stopAccessingSecurityScopedResource() } }
                guard let d = try? Data(contentsOf: u) else { return nil }
                return PickedImage(data: d, name: u.lastPathComponent)
            }
            if !out.isEmpty { onPick(out) }
        }
        .sheet(isPresented: $showLibrary) {
            LibraryPicker(filter: { $0.isImage }, multiple: multiple) { files in
                let out = files.compactMap { f in (try? Data(contentsOf: f.url)).map { PickedImage(data: $0, name: f.name) } }
                if !out.isEmpty { onPick(out) }
            }
        }
    }
}

struct PickedImage: Identifiable {
    let id = UUID()
    let data: Data
    let name: String
    var baseName: String { (name as NSString).deletingPathExtension }
    var image: UIImage? { UIImage(data: data) }
}

// MARK: - Running a tool

/// Runs a tool's work off the main thread and holds its outcome.
@MainActor
final class ToolRunner: ObservableObject {
    @Published var busy = false
    @Published var progress: Double?
    @Published var error: String?
    @Published var result: ToolResult?

    func run(_ work: @escaping (_ progress: @escaping (Double) -> Void) throws -> ToolResult) {
        guard !busy else { return }
        busy = true
        progress = nil
        error = nil
        let report: (Double) -> Void = { p in Task { @MainActor in self.progress = p } }
        Task.detached(priority: .userInitiated) {
            do {
                let r = try work(report)
                await MainActor.run {
                    self.busy = false
                    self.progress = nil
                    FileLibrary.shared.refresh()
                    self.result = r
                }
            } catch {
                await MainActor.run {
                    self.busy = false
                    self.progress = nil
                    self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }
}

struct ToolResult: Identifiable {
    let id = UUID()
    var files: [LibraryFile]
    var message: String
    /// Images that can also be saved to the photo library.
    var images: [URL] = []
}

struct ToolError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

extension View {
    /// Shows the result sheet and error alerts for a runner.
    func toolRunner(_ runner: ToolRunner) -> some View {
        modifier(ToolRunnerModifier(runner: runner))
    }
}

private struct ToolRunnerModifier: ViewModifier {
    @ObservedObject var runner: ToolRunner
    func body(content: Content) -> some View {
        content
            .overlay {
                if runner.busy {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        VStack(spacing: 14) {
                            if let p = runner.progress {
                                ProgressView(value: p).frame(width: 180)
                                Text("\(Int(p * 100))%").font(.caption).foregroundStyle(.secondary)
                            } else {
                                ProgressView().controlSize(.large)
                            }
                            Text("Working…").font(.headline)
                        }
                        .padding(28)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
            .alert("Something went wrong", isPresented: Binding(get: { runner.error != nil }, set: { if !$0 { runner.error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(runner.error ?? "") }
            .sheet(item: $runner.result) { r in ResultSheet(result: r) }
    }
}

/// What a tool made: preview, share, save to Files or Photos.
struct ResultSheet: View {
    let result: ToolResult
    @Environment(\.dismiss) var dismiss
    @State private var preview: LibraryFile?
    @State private var photosMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green)
                        Text(result.message).font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
                Section(result.files.count == 1 ? "Your file" : "Your files (\(result.files.count))") {
                    ForEach(result.files) { f in
                        Button { preview = f } label: { FileRow(file: f) }.buttonStyle(.plain)
                    }
                }
                Section {
                    ShareLink(items: result.files.map(\.url)) {
                        Label(result.files.count == 1 ? "Share" : "Share all", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        FilesExporter.present(result.files.map(\.url))
                    } label: { Label("Save to Files…", systemImage: "folder.badge.plus") }
                    if !result.images.isEmpty {
                        Button {
                            PhotoSaver.save(result.images) { msg in photosMessage = msg }
                        } label: { Label("Save to Photos", systemImage: "photo.badge.plus") }
                    }
                } footer: {
                    Text("Also saved in the Files tab.")
                }
            }
            .navigationTitle("Done")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(item: $preview) { f in FileOpener(file: f) }
            .alert(photosMessage ?? "", isPresented: Binding(get: { photosMessage != nil }, set: { if !$0 { photosMessage = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

struct FileRow: View {
    let file: LibraryFile
    var body: some View {
        HStack(spacing: 12) {
            FileThumbnail(url: file.url, symbol: file.symbol)
                .frame(width: 44, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name).font(.subheadline.weight(.medium)).lineLimit(2)
                Text("\(file.sizeText) · \(file.modified.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// A small preview of a PDF's first page or an image.
struct FileThumbnail: View {
    let url: URL
    var symbol: String = "doc.fill"
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Theme.iconTile)
            if let image {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 4)).padding(2)
            } else {
                Image(systemName: symbol).foregroundStyle(Theme.accent)
            }
        }
        .task(id: url) { image = await Thumbnails.make(url, size: CGSize(width: 120, height: 160)) }
    }
}

enum Thumbnails {
    static func make(_ url: URL, size: CGSize) async -> UIImage? {
        await Task.detached(priority: .utility) { () -> UIImage? in
            if url.pathExtension.lowercased() == "pdf" {
                guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
                return page.thumbnail(of: size, for: .cropBox)
            }
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                         kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height) * 2,
                                         kCGImageSourceCreateThumbnailWithTransform: true]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
    }
}

// MARK: - System screens

/// "Save to Files…" — lets the user pick a folder to copy files into. Presented straight from UIKit
/// on top of whatever is showing, so the files are always handed over.
enum FilesExporter {
    @MainActor
    static func present(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        let picker = UIDocumentPickerViewController(forExporting: existing, asCopy: true)
        picker.shouldShowFileExtensions = true
        topViewController()?.present(picker, animated: true)
    }

    @MainActor
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}

struct QuickLookScreen: View {
    let urls: [URL]
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            QuickLookView(urls: urls)
                .ignoresSafeArea(edges: .bottom)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { ShareLink(items: urls) }
                }
        }
    }
}

struct QuickLookView: UIViewControllerRepresentable {
    let urls: [URL]
    func makeCoordinator() -> Coordinator { Coordinator(urls: urls) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }
    func updateUIViewController(_ vc: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let urls: [URL]
        init(urls: [URL]) { self.urls = urls }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { urls.count }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { urls[index] as NSURL }
    }
}

enum PhotoSaver {
    static func save(_ urls: [URL], done: @escaping (String) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { done("Allow Ski PDF to add photos in Settings › Privacy › Photos.") }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                for u in urls { PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: u) }
            }) { ok, _ in
                DispatchQueue.main.async { done(ok ? "Saved \(urls.count) image\(urls.count == 1 ? "" : "s") to Photos." : "Couldn't save to Photos.") }
            }
        }
    }
}

/// A chosen-PDF summary row with a remove button.
struct PickedPDFRow: View {
    let pdf: PickedPDF
    var onRemove: (() -> Void)?
    var body: some View {
        HStack(spacing: 12) {
            FileThumbnail(url: pdf.url, symbol: "doc.richtext.fill").frame(width: 44, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(pdf.name).font(.subheadline.weight(.medium)).lineLimit(2)
                Text("\(pdf.pageCount) page\(pdf.pageCount == 1 ? "" : "s")" + (pdf.isLocked ? " · locked" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
        }
    }
}

/// Standard layout for single-PDF tools: pick a PDF, set options, run.
struct SinglePDFToolLayout<Options: View>: View {
    @Binding var pdf: PickedPDF?
    var allowLocked: Bool = false
    var actionTitle: String
    var actionSymbol: String = "sparkles"
    var actionDisabled: Bool = false
    var busy: Bool
    var hint: String? = nil
    let action: () -> Void
    @ViewBuilder var options: Options

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let hint { Text(hint).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                if let p = pdf {
                    Panel(title: "PDF") {
                        PickedPDFRow(pdf: p) { pdf = nil }
                    }
                    options
                } else {
                    PDFPicker(allowLocked: allowLocked) { pdf = $0.first }
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            if pdf != nil {
                PrimaryButton(title: actionTitle, systemImage: actionSymbol, busy: busy, disabled: actionDisabled, action: action)
                    .padding(.horizontal, 16).padding(.bottom, 8)
                    .background(Theme.background.opacity(0.95))
            }
        }
        .toolBackground()
    }
}

/// Parses "1-3, 5, 8-" style page lists (1-based) into 0-based indexes, in order, without duplicates.
enum PageRange {
    static func parse(_ text: String, count: Int) -> [Int]? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return Array(0..<count) }
        var out: [Int] = []
        var seen = Set<Int>()
        for part in trimmed.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " }) {
            let p = part.trimmingCharacters(in: .whitespaces)
            if p.isEmpty { continue }
            let ends = p.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            var a: Int, b: Int
            if ends.count == 1 {
                guard let v = Int(ends[0]) else { return nil }
                a = v; b = v
            } else if ends.count == 2 {
                a = ends[0].isEmpty ? 1 : (Int(ends[0]) ?? -1)
                b = ends[1].isEmpty ? count : (Int(ends[1]) ?? -1)
                if a < 0 || b < 0 { return nil }
            } else { return nil }
            if a < 1 || b < 1 || a > count || b > count { return nil }
            let range = a <= b ? Array(a...b) : Array((b...a).reversed())
            for i in range where !seen.contains(i - 1) {
                seen.insert(i - 1)
                out.append(i - 1)
            }
        }
        return out.isEmpty ? nil : out
    }
}
