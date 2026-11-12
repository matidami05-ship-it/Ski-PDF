import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @EnvironmentObject var library: FileLibrary
    @EnvironmentObject var router: Router
    @State private var search = ""
    @State private var kind = Kind.all
    @State private var renaming: LibraryFile?
    @State private var newName = ""
    @State private var deleting: LibraryFile?
    @State private var showImporter = false

    enum Kind: String, CaseIterable, Identifiable {
        case all = "All", pdf = "PDFs", images = "Images", other = "Other"
        var id: String { rawValue }
    }

    private var shown: [LibraryFile] {
        library.files.filter { f in
            let k: Bool
            switch kind {
            case .all: k = true
            case .pdf: k = f.isPDF
            case .images: k = f.isImage
            case .other: k = !f.isPDF && !f.isImage
            }
            return k && (search.isEmpty || f.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.files.isEmpty {
                    ContentUnavailableView {
                        Label("No files yet", systemImage: "folder")
                    } description: {
                        Text("Everything you make with the tools is saved here. You can also import files to work on.")
                    } actions: {
                        Button("Import Files") { showImporter = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Picker("Kind", selection: $kind) {
                            ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        ForEach(shown) { f in
                            Button { router.opened = f } label: { FileRow(file: f) }
                                .buttonStyle(.plain)
                                .contextMenu { menu(f) }
                                .swipeActions {
                                    Button(role: .destructive) { deleting = f } label: { Label("Delete", systemImage: "trash") }
                                    Button { startRename(f) } label: { Label("Rename", systemImage: "pencil") }.tint(.indigo)
                                }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .toolBackground()
            .navigationTitle("Files")
            .searchable(text: $search, prompt: "Search files")
            .refreshable { library.refresh() }
            .onAppear { library.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                        .accessibilityLabel("Import files")
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { for u in urls { _ = library.importFile(from: u) } }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") { if let f = renaming { library.rename(f, to: newName) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let f = deleting { library.delete(f) }; deleting = nil }
            }
        }
    }

    @ViewBuilder
    private func menu(_ f: LibraryFile) -> some View {
        Button { router.opened = f } label: { Label("Open", systemImage: "eye") }
        ShareLink(item: f.url) { Label("Share", systemImage: "square.and.arrow.up") }
        Button { FilesExporter.present([f.url]) } label: { Label("Save to Files…", systemImage: "folder.badge.plus") }
        Button { startRename(f) } label: { Label("Rename", systemImage: "pencil") }
        Button { library.duplicate(f) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button(role: .destructive) { deleting = f } label: { Label("Delete", systemImage: "trash") }
    }

    private func startRename(_ f: LibraryFile) {
        newName = f.baseName
        renaming = f
    }
}

struct IdentURL: Identifiable {
    let url: URL
    var id: URL { url }
}
