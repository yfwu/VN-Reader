import Foundation
import ComicCore
struct ErrorExplanation: Equatable { var title: String; var message: String }
enum ErrorMessages { static func explain(_ error: Error) -> ErrorExplanation { .init(title: "Error", message: String(describing: error)) } }
enum L10n {
    static let libraryRecovered = "recovered", libraryUnavailable = "unavailable", libraryUnsupportedVersion = "unsupported", libraryOrphansPreserved = "orphans"
    static func volumeName(_ value: String) -> String { "Vol. \(value)" }
}
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
    func beginBackgroundTask(withName: String, expirationHandler: @escaping () -> Void) -> UIBackgroundTaskIdentifier { .init(value: 1) }
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {}
}
struct ImageIOCoverRenderer: CoverRendering { func coverJPEG(from imageData: Data) -> Data? { nil } }
