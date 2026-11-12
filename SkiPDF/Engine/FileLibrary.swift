import Foundation
import UniformTypeIdentifiers
import SwiftUI

/// A file kept in Ski PDF's own folder (visible in the Files app under On My iPhone › Ski PDF).
struct LibraryFile: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let modified: Date

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var baseName: String { url.deletingPathExtension().lastPathComponent }
    var ext: String { url.pathExtension.lowercased() }
    var isPDF: Bool { ext == "pdf" }
    var isImage: Bool { ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"].contains(ext) }

    var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }

    var symbol: String {
        if isPDF { return "doc.richtext.fill" }
        if isImage { return "photo.fill" }
        switch ext {
        case "txt": return "doc.plaintext.fill"
        case "zip": return "doc.zipper"
        default: return "doc.fill"
        }
    }
}

final class FileLibrary: ObservableObject {
    static let shared = FileLibrary()

    @Published private(set) var files: [LibraryFile] = []

    let folder: URL

    private init() {
        folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        refresh()
    }

    func refresh() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let list = urls.compactMap { u -> LibraryFile? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { return nil }
            return LibraryFile(url: u, size: Int64(v.fileSize ?? 0), modified: v.contentModificationDate ?? .distantPast)
        }
        let sorted = list.sorted { $0.modified > $1.modified }
        if Thread.isMainThread { files = sorted } else { DispatchQueue.main.async { self.files = sorted } }
    }

    /// A free file name in the library: "Report.pdf", "Report 2.pdf", …
    func uniqueURL(_ name: String) -> URL {
        let clean = FileLibrary.sanitize(name)
        let base = (clean as NSString).deletingPathExtension
        let ext = (clean as NSString).pathExtension
        var candidate = folder.appendingPathComponent(clean)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    static func sanitize(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let s = name.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "File" : s
    }

    /// Saves data as a new library file and returns it.
    @discardableResult
    func save(_ data: Data, name: String) throws -> LibraryFile {
        let url = uniqueURL(name)
        try data.write(to: url, options: .atomic)
        refresh()
        return file(for: url)
    }

    /// Moves a temporary file into the library.
    @discardableResult
    func adopt(_ temp: URL, name: String) throws -> LibraryFile {
        let url = uniqueURL(name)
        try FileManager.default.moveItem(at: temp, to: url)
        refresh()
        return file(for: url)
    }

    func file(for url: URL) -> LibraryFile {
        let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return LibraryFile(url: url, size: Int64(v?.fileSize ?? 0), modified: v?.contentModificationDate ?? Date())
    }

    /// Copies a file from elsewhere (Files app, another app) into the library.
    func importFile(from url: URL) -> LibraryFile? {
        if url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
            return file(for: url)
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dest = uniqueURL(url.lastPathComponent)
        do {
            var err: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &err) { readURL in
                do { try FileManager.default.copyItem(at: readURL, to: dest) } catch { copyError = error }
            }
            if let e = err ?? copyError as NSError? { throw e }
            refresh()
            return file(for: dest)
        } catch {
            return nil
        }
    }

    func delete(_ f: LibraryFile) {
        try? FileManager.default.removeItem(at: f.url)
        refresh()
    }

    func rename(_ f: LibraryFile, to newName: String) {
        var name = FileLibrary.sanitize(newName)
        if (name as NSString).pathExtension.isEmpty && !f.ext.isEmpty { name += "." + f.ext }
        guard name != f.name else { return }
        let dest = uniqueURL(name)
        try? FileManager.default.moveItem(at: f.url, to: dest)
        refresh()
    }

    func duplicate(_ f: LibraryFile) {
        let dest = uniqueURL(f.baseName + " copy" + (f.ext.isEmpty ? "" : "." + f.ext))
        try? FileManager.default.copyItem(at: f.url, to: dest)
        refresh()
    }
}

/// A scratch folder for work in progress, emptied at launch.
enum Scratch {
    static let folder: URL = {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("work", isDirectory: true)
        try? FileManager.default.removeItem(at: u)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    static func url(_ name: String) -> URL {
        let dir = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(FileLibrary.sanitize(name))
    }

    /// Copies a picked file somewhere the app can keep reading it.
    static func copyIn(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dest = Scratch.url(url.lastPathComponent)
        var err: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &err) { readURL in
            do { try FileManager.default.copyItem(at: readURL, to: dest) } catch { copyError = error }
        }
        if let e = err { throw e }
        if let e = copyError { throw e }
        return dest
    }
}
