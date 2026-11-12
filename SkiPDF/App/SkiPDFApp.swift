import SwiftUI

@main
struct SkiPDFApp: App {
    @StateObject private var library = FileLibrary.shared
    @StateObject private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(router)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // "Open in Ski PDF" / Share from another app: copy it into the library and open it.
                    if let saved = library.importFile(from: url) {
                        router.open(saved)
                    }
                }
        }
    }
}

/// App-wide navigation: which tab is showing and any file opened from outside.
final class Router: ObservableObject {
    enum Tab: Hashable { case tools, files }
    @Published var tab: Tab = .tools
    @Published var opened: LibraryFile?

    func open(_ file: LibraryFile) {
        tab = .files
        opened = file
    }
}

struct RootView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var library: FileLibrary

    var body: some View {
        TabView(selection: $router.tab) {
            ToolsView()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver.fill") }
                .tag(Router.Tab.tools)
            FilesView()
                .tabItem { Label("Files", systemImage: "folder.fill") }
                .tag(Router.Tab.files)
        }
        .fullScreenCover(item: $router.opened) { file in
            FileOpener(file: file)
        }
    }
}

/// Opens a library file in the right place: PDFs in the viewer, everything else in Quick Look.
struct FileOpener: View {
    let file: LibraryFile
    var body: some View {
        if file.isPDF {
            PDFViewerScreen(url: file.url)
        } else {
            QuickLookScreen(urls: [file.url])
        }
    }
}
