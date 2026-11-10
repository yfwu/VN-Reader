import Foundation
import ComicCore

struct CheckFailure: Error { let message: String }
func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    guard value() else { throw CheckFailure(message: message) }
    print("PASS: \(message)")
}

@main struct Audit {
    @MainActor static func main() throws {
        let defaults = HarnessDefaults.store
        defer { defaults.removePersistentDomain(forName: HarnessDefaults.suite) }
        let isMac = ReaderLayoutPreferences.currentPlatformIsMac
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var book = BookRecord(displayName: "Synthetic", originalFileName: "test.cbz", format: .zip,
                              isSolid: false, fileSize: 128, pageCount: 20, fingerprint: "test", hasCover: false)
        book.layout = .single
        book.syncState = BookSyncState(contentID: String(repeating: "a", count: 64), book: book, device: "test")
        book.syncAccountID = "synthetic-account"
        let original = book
        let library = LibraryStore(book: book, root: root)
        let settings = AppSettings.auditMake()
        let model = ReaderViewModel(record: book, library: library, settings: settings)
        let pager = PagerSpy(); model.pager = pager
        try check(settings.defaultLayout == (isMac ? .double : .single), "platform default layout is correct")
        try check(model.layout == (isMac ? .double : .single), "existing synced single book gets the correct effective layout")
        try check(model.record == original && library.updates == 0, "opening with a default never rewrites the book or sync fields")

        var webtoon = book; webtoon.id = UUID(); webtoon.layout = .vertical
        let verticalModel = ReaderViewModel(record: webtoon, library: LibraryStore(book: webtoon, root: root), settings: settings)
        try check(verticalModel.layout == .vertical, "vertical webtoon retains its layout")

        if isMac {
            // record.layout already equals single; the explicit selection still
            // must be saved instead of being ignored by an old equality guard.
            model.setLayout(.single)
            try check(model.layout == .single && pager.reloads == 1, "explicit Mac single overrides double and refreshes the pager")
            try check(model.record == original && library.book(book.id) == original && library.updates == 0,
                      "Mac selection leaves BookRecord and cloud state byte-for-byte equivalent")
            defaults.synchronize()
            let restarted = ReaderViewModel(record: book, library: library, settings: AppSettings.auditMake())
            try check(restarted.layout == .single, "explicit single survives settings and reader reconstruction")
            let reloadedDefaults = UserDefaults(suiteName: HarnessDefaults.suite)!
            let reloaded = ReaderLayoutPreferences(defaults: reloadedDefaults, isMac: true)
            try check(reloaded.layout(for: book, defaultLayout: .double) == .single, "explicit single is persisted in device-local defaults")
            settings.defaultLayout = .vertical
            try check(model.layout == .single, "per-book choice wins over later global preference")
            var other = book; other.id = UUID()
            try check(settings.readerLayout(for: other) == .vertical, "another local book does not inherit the first book override")
            defaults.set(PageLayout.single.rawValue, forKey: "defaultLayout")
            let explicitGlobal = AppSettings.auditMake()
            try check(explicitGlobal.defaultLayout == .single && explicitGlobal.readerLayout(for: other) == .single,
                      "existing explicit global single preference is respected")
            try check(explicitGlobal.readerLayout(for: webtoon) == .vertical, "explicit global single does not flatten a vertical book")
        } else {
            settings.defaultLayout = .double
            try check(model.layout == .single, "iPad global defaults do not change an existing book")
            model.setLayout(.double)
            try check(model.layout == .double && library.book(book.id)?.layout == .double && library.updates == 1,
                      "iPad setLayout retains the existing BookRecord update behavior")
            try check(pager.reloads == 1, "iPad layout selection refreshes the pager")
            let overrides = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("reader.mac.layout.") }
            try check(overrides.isEmpty, "iPad selection never creates a Mac local override")
        }
        print("All actual AppSettings/ReaderViewModel layout checks passed: \(isMac ? "Mac" : "iPad")")
    }
}
