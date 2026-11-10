import UIKit
import ComicCore

struct ErrorExplanation { let title: String; let message: String }
enum ErrorMessages {
    static func explain(_ error: Error) -> ErrorExplanation { .init(title: "Error", message: String(describing: error)) }
    static func imageTooLarge(_ width: Int, _ height: Int) -> ErrorExplanation { .init(title: "Large", message: "") }
    static func imageDecodeFailed(_ path: String) -> ErrorExplanation { .init(title: "Decode", message: path) }
}
enum L10n {
    static let retry = "Retry", firstPage = "First", lastPage = "Last"
    static func pageNumber(_ page: Int) -> String { String(page) }
}
struct PageOnScreen { let page: Int; let image: UIImage; let frame: CGRect }
struct AuditBackground { var uiColor: UIColor { .black } }
final class AuditSettings {
    var coverAlone = false, shiftSpreads = false, animatePageTurns = true, tapToTurn = true
    var background = AuditBackground()
}
@MainActor final class ReaderViewModel {
    var record = BookRecord(displayName: "Synthetic", originalFileName: "synthetic.cbz", format: .zip,
                            isSolid: false, fileSize: 1, pageCount: 6, fingerprint: "synthetic", hasCover: false)
    var layout = PageLayout.double
    var currentPage = 0
    var visiblePages: [Int] = []
    var pageEvents: [(page: Int, userInitiated: Bool)] = []
    var userPageEvents: [Int] { pageEvents.filter(\.userInitiated).map(\.page) }
    var widePages: Set<Int> = []
    var chromeVisible = false
    let settings = AuditSettings()
    weak var pager: ReaderPaging?
    var loader: PageImageLoader?
    var pageCount: Int { record.pageCount }
    var loupeAccessibilityAction: UIAccessibilityCustomAction { .init(name: "Loupe", actionHandler: { _ in true }) }
    func holdLoupe(_ press: UILongPressGestureRecognizer) {}
    func containerSizeChanged(_ size: CGSize, scale: CGFloat) {}
    func toggleChrome() { chromeVisible.toggle() }
    func setChrome(_ visible: Bool) { chromeVisible = visible }
    func flash(_ text: String) {}
    func pageDidChange(_ page: Int, visiblePages: [Int], userInitiated: Bool) {
        if userInitiated { currentPage = page }
        self.visiblePages = visiblePages
        pageEvents.append((page, userInitiated))
    }
}
