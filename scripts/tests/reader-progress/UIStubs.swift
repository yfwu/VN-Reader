import SwiftUI
import ComicCore
struct ErrorExplanation: Equatable { var title: String; var message: String }
enum ErrorMessages { static func explain(_ error: Error) -> ErrorExplanation { .init(title: "Error", message: String(describing: error)) } }
enum LibrarySort { case recentlyRead, imported, title, series }
enum LibraryFilter { case all, unread, reading, finished, favorites }
@MainActor final class AppSettings {
    static let shared = AppSettings()
    let defaultDirection = ReadingDirection.leftToRight
    let defaultFitMode = PageFitMode.fitPage
    let defaultLayout = PageLayout.single
    func readerLayout(for book: BookRecord) -> PageLayout { book.layout }
    func storeLocalReaderLayout(_ layout: PageLayout, for id: UUID) -> Bool { false }
}
@MainActor final class CoverCache { static let shared = CoverCache(); func invalidate(_ url: URL) {} }
struct UIBackgroundTaskIdentifier: Equatable, Sendable { let value: Int; static let invalid = Self(value: -1) }
@MainActor final class UIApplication {
    static let shared = UIApplication()
    func registerForRemoteNotifications() { fatalError("Network registration forbidden") }
    func beginBackgroundTask(withName: String, expirationHandler: @escaping () -> Void) -> UIBackgroundTaskIdentifier { .init(value: 1) }
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {}
}
struct ImageIOCoverRenderer: CoverRendering { func coverJPEG(from imageData: Data) -> Data? { nil } }
@MainActor enum HarnessDefaults { static let store = InMemoryDefaults() }
@MainActor final class InMemoryDefaults {
    private var values: [String: Any] = [:]
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func string(forKey key: String) -> String? { values[key] as? String }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}
enum CloudSyncEnvironment {
    static let smokeRunID: String? = nil
    static let smokeClientID = "offline-audit"
    static let defaultsPrefix = "offline-audit-" + UUID().uuidString + "."
    static func zoneName(_ name: String) -> String { "OfflineAudit-" + name }
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

@MainActor protocol ReaderPaging: AnyObject {
    func go(toPage: Int, animated: Bool, userInitiated: Bool)
    func widePagesChanged()
    func reloadForSettings()
}
@MainActor final class PagerSpy: ReaderPaging {
    var reloads = 0
    var restorations: [(Int, Bool)] = []
    func go(toPage: Int, animated: Bool, userInitiated: Bool) { restorations.append((toPage, userInitiated)) }
    func widePagesChanged() {}
    func reloadForSettings() { reloads += 1 }
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
