import SwiftUI
import ComicCore

/// Launch arguments used by UI tests and screenshot runs. They have no effect
/// in normal use.
///   -ui-testing     start from an empty library and default settings
///   -seed-samples   import the bundled sample books (Resources/Samples)
///   -open-first     open the first book after seeding
enum UITestSupport {
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing") }
    static var shouldSeed: Bool { ProcessInfo.processInfo.arguments.contains("-seed-samples") }

    static func prepareEnvironment() {
        guard isUITesting else { return }
        AppSettings.shared.resetForTesting()
        if let paths = try? LibraryPaths.standard() {
            try? FileManager.default.removeItem(at: paths.root)
            try? FileManager.default.removeItem(at: paths.cachesRoot)
            try? FileManager.default.removeItem(at: paths.tempRoot)
        }
    }

    @MainActor
    static func seedIfRequested(library: LibraryStore, importer: ImportCoordinator) {
        guard shouldSeed, library.books.isEmpty else { return }
        // Synchronized Xcode groups flatten resources into the bundle root.
        let urls = ["cbz", "cbr"].flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        importer.importFiles(urls, securityScoped: false)
    }
}
