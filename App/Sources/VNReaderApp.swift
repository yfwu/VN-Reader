import SwiftUI
import ComicCore

@main
struct VNReaderApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var importer: ImportCoordinator

    init() {
        UITestSupport.prepareEnvironment()
        let paths: LibraryPaths
        do { paths = try LibraryPaths.standard() } catch {
            fatalError("Application Support is unavailable: \(error)")
        }
        let lib = LibraryStore(paths: paths)
        _library = StateObject(wrappedValue: lib)
        _importer = StateObject(wrappedValue: ImportCoordinator(library: lib))
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(importer)
                .onOpenURL { url in
                    // Files from "Open in…", AirDrop or the share sheet are copied
                    // into our Inbox by the system; import and remove that copy.
                    let inbox = url.path.contains("/Documents/Inbox/")
                    importer.importFiles([url], securityScoped: !inbox, deleteAfterImport: inbox)
                }
                .task { UITestSupport.seedIfRequested(library: library, importer: importer) }
        }
    }
}
