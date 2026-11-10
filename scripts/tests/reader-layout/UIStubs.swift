import SwiftUI
import ComicCore

enum HarnessDefaults {
    static let suite = "VNReader.LayoutAudit." + UUID().uuidString
    static let store = UserDefaults(suiteName: suite)!
}
struct UIColor {
    init(white: CGFloat = 0, alpha: CGFloat = 1) {}
    static let black = Self(), gray = Self(), white = Self(), systemBackground = Self()
}
struct UIScreen {
    static let main = Self()
    let bounds = CGRect(x: 0, y: 0, width: 1024, height: 768)
    let scale: CGFloat = 1
}
@MainActor final class UILongPressGestureRecognizer {
    enum State { case began, changed, ended }
    var state = State.ended
    func location(in view: Any?) -> CGPoint { .zero }
}
@MainActor final class UIAccessibilityCustomAction {
    init(name: String, actionHandler: @escaping (UIAccessibilityCustomAction) -> Bool) {}
}
enum UIAccessibility {
    enum Notification { case announcement }
    static func post(notification: Notification, argument: Any?) {}
}
struct ErrorExplanation: Equatable { var title: String; var message: String }
enum ErrorMessages {
    static func explain(_ error: Error) -> ErrorExplanation { .init(title: "error", message: "test") }
}
@MainActor protocol ReaderPaging: AnyObject {
    func go(toPage: Int, animated: Bool, userInitiated: Bool)
    func widePagesChanged()
    func reloadForSettings()
}
@MainActor final class PagerSpy: ReaderPaging {
    var reloads = 0
    func go(toPage: Int, animated: Bool, userInitiated: Bool) {}
    func widePagesChanged() {}
    func reloadForSettings() { reloads += 1 }
}
@MainActor final class CloudStub {
    enum AutomaticSyncReason { case bookOpened, bookClosed, readerForeground }
    func requestAutomaticSync(_ reason: AutomaticSyncReason) {}
    func ensureDownloaded(_ id: UUID, progress: @escaping @MainActor (Double) -> Void) async throws {
        fatalError("Network/download use is forbidden in layout audit")
    }
    func explain(_ error: Error) -> String { "test" }
}
@MainActor final class LibraryStore {
    let paths: LibraryPaths
    let cloudSync = CloudStub()
    @Published var books: [BookRecord]
    var updates = 0
    init(book: BookRecord, root: URL) {
        books = [book]
        paths = LibraryPaths(root: root, cachesRoot: root, tempRoot: root)
    }
    func book(_ id: UUID) -> BookRecord? { books.first { $0.id == id } }
    func update(_ id: UUID, _ change: (inout BookRecord) -> Void, immediate: Bool = false) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        change(&books[index]); updates += 1
    }
    func acquireReaderLease(_ id: UUID) -> UUID { UUID() }
    func releaseReaderLease(_ lease: UUID) {}
    func isDownloaded(_ book: BookRecord) -> Bool { false }
    func recordPosition(_ id: UUID, page: Int, reachedEnd: Bool = false) {}
    func recordOpened(_ id: UUID) {}
    func saveNow() {}
}
@MainActor final class PageImageLoader {
    var onDecoded: ((Int, CGSize) -> Void)?
    init(source: BookPageSource, targetPixelSize: CGSize) {}
    func updateTarget(_ size: CGSize) {}
    func endDetail() {}
    func cancelAll() {}
}
@MainActor final class ThumbnailProvider {
    init(source: BookPageSource, cacheDir: URL) {}
    func cancelAll() {}
}
enum SharedPageFiles {
    static func write(pages: [Int], source: BookPageSource, bookName: String) throws -> [URL] {
        fatalError("Archive/share work is forbidden in layout audit")
    }
    static func removeAll() {}
}
func onMain(_ body: @escaping @MainActor () -> Void) { Task { @MainActor in body() } }
