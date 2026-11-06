import Foundation

/// The bundled user guide (scripts/guide/generate_guide.py), the only CBZ in the app.
/// It is imported like any other book, so people can delete it and add it back.
@MainActor
enum UserGuide {
    private static let offeredKey = "userGuideOffered"

    /// Gives a new library its first book. Runs once, so a deleted guide stays deleted.
    static func addOnFirstLaunch(library: LibraryStore, importer: ImportCoordinator) {
        guard !UITestSupport.isUITesting else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: offeredKey) else { return }
        defaults.set(true, forKey: offeredKey)
        if library.books.isEmpty { add(to: importer) }
    }

    static func add(to importer: ImportCoordinator) {
        guard let url = Bundle.main.url(forResource: nil, withExtension: "cbz") else { return }
        importer.importFiles([url], securityScoped: false)
    }
}
