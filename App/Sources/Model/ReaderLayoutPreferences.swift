import Foundation
import ComicCore

/// Layout is a local display preference. Mac defaults must not rewrite the
/// catalogue's layout, including books received from another device.
final class ReaderLayoutPreferences {
    private static let overridePrefix = "reader.mac.layout."
    private let defaults: UserDefaults
    private let isMac: Bool

    static var currentPlatformIsMac: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    init(defaults: UserDefaults, isMac: Bool = ReaderLayoutPreferences.currentPlatformIsMac) {
        self.defaults = defaults
        self.isMac = isMac
    }

    var defaultLayout: PageLayout {
        PageLayout(rawValue: defaults.string(forKey: "defaultLayout") ?? "") ?? (isMac ? .double : .single)
    }

    func layout(for book: BookRecord, defaultLayout: PageLayout) -> PageLayout {
        guard isMac else { return book.layout }
        if let value = defaults.string(forKey: Self.overridePrefix + book.id.uuidString),
           let choice = PageLayout(rawValue: value) { return choice }
        // Keep intentionally vertical books/webtoons when adopting the Mac default.
        if book.layout == .vertical { return .vertical }
        return defaultLayout
    }

    /// Returns false on iPad, where the existing BookRecord setter remains in use.
    @discardableResult
    func storeLocalSelection(_ layout: PageLayout, for bookID: UUID) -> Bool {
        guard isMac else { return false }
        defaults.set(layout.rawValue, forKey: Self.overridePrefix + bookID.uuidString)
        return true
    }

    func resetLocalSelections() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.overridePrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
