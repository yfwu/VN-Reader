import Foundation
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
