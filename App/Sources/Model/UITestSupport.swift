import SwiftUI
import ComicCore

/// Launch arguments used by UI tests and screenshot runs. They have no effect
/// in normal use.
///   -ui-testing     start from an empty library and default settings
///   -seed-samples <folder>   import the books in that folder (UITests/Samples, simulator only)
///   -open-first     open the first book after seeding
enum UITestSupport {
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing") }
    static var seedFolder: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: "-seed-samples"), i + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
    }

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
        guard let seedFolder, library.books.isEmpty else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: seedFolder, includingPropertiesForKeys: nil)) ?? []
        let urls = files.filter { ["cbz", "cbr"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        importer.importFiles(urls, securityScoped: false)
    }
}
