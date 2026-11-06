import SwiftUI
import ComicCore

enum ReaderBackground: String, CaseIterable, Identifiable {
    case black, gray, white, system
    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: return L10n.bgBlack
        case .gray: return L10n.bgGray
        case .white: return L10n.bgWhite
        case .system: return L10n.bgSystem
        }
    }

    var uiColor: UIColor {
        switch self {
        case .black: return .black
        case .gray: return UIColor(white: 0.16, alpha: 1)
        case .white: return .white
        case .system: return .systemBackground
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recentlyRead, imported, title, series
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recentlyRead: return L10n.sortRecent
        case .imported: return L10n.sortImported
        case .title: return L10n.sortTitle
        case .series: return L10n.sortSeries
        }
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, unread, reading, finished, favorites
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return L10n.filterAll
        case .unread: return L10n.statusUnread
        case .reading: return L10n.statusReading
        case .finished: return L10n.statusFinished
        case .favorites: return L10n.filterFavorites
        }
    }
}

/// App-wide preferences (UserDefaults). Per-book settings live in BookRecord.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var defaultDirection: ReadingDirection { didSet { d.set(defaultDirection.rawValue, forKey: "defaultDirection") } }
    @Published var defaultFitMode: PageFitMode { didSet { d.set(defaultFitMode.rawValue, forKey: "defaultFitMode") } }
    @Published var defaultLayout: PageLayout { didSet { d.set(defaultLayout.rawValue, forKey: "defaultLayout") } }
    @Published var background: ReaderBackground { didSet { d.set(background.rawValue, forKey: "readerBackground") } }
    @Published var tapToTurn: Bool { didSet { d.set(tapToTurn, forKey: "tapToTurn") } }
    @Published var animatePageTurns: Bool { didSet { d.set(animatePageTurns, forKey: "animatePageTurns") } }
    @Published var coverAlone: Bool { didSet { d.set(coverAlone, forKey: "coverAlone") } }
    @Published var shiftSpreads: Bool { didSet { d.set(shiftSpreads, forKey: "shiftSpreads") } }
    @Published var sort: LibrarySort { didSet { d.set(sort.rawValue, forKey: "librarySort") } }
    @Published var filter: LibraryFilter { didSet { d.set(filter.rawValue, forKey: "libraryFilter") } }
    @Published var loupeDiameter: Double { didSet { d.set(loupeDiameter, forKey: "loupeDiameter") } }
    @Published var loupeMagnification: Double { didSet { d.set(loupeMagnification, forKey: "loupeMagnification") } }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: ["tapToTurn": true, "animatePageTurns": true, "coverAlone": true,
                              "loupeDiameter": 260.0, "loupeMagnification": 2.5])
        defaultDirection = ReadingDirection(rawValue: d.string(forKey: "defaultDirection") ?? "") ?? .leftToRight
        defaultFitMode = PageFitMode(rawValue: d.string(forKey: "defaultFitMode") ?? "") ?? .fitPage
        defaultLayout = PageLayout(rawValue: d.string(forKey: "defaultLayout") ?? "") ?? .single
        background = ReaderBackground(rawValue: d.string(forKey: "readerBackground") ?? "") ?? .black
        tapToTurn = d.bool(forKey: "tapToTurn")
        animatePageTurns = d.bool(forKey: "animatePageTurns")
        coverAlone = d.bool(forKey: "coverAlone")
        shiftSpreads = d.bool(forKey: "shiftSpreads")
        sort = LibrarySort(rawValue: d.string(forKey: "librarySort") ?? "") ?? .recentlyRead
        filter = LibraryFilter(rawValue: d.string(forKey: "libraryFilter") ?? "") ?? .all
        loupeDiameter = d.double(forKey: "loupeDiameter")
        loupeMagnification = d.double(forKey: "loupeMagnification")
    }

    /// Restores defaults (UI tests start from a known state).
    func resetForTesting() {
        for k in ["defaultDirection", "defaultFitMode", "defaultLayout", "readerBackground", "tapToTurn",
                  "animatePageTurns", "coverAlone", "shiftSpreads", "librarySort", "libraryFilter",
                  "loupeDiameter", "loupeMagnification"] {
            d.removeObject(forKey: k)
        }
        defaultDirection = .leftToRight
        defaultFitMode = .fitPage
        defaultLayout = .single
        background = .black
        tapToTurn = true
        animatePageTurns = true
        coverAlone = true
        shiftSpreads = false
        sort = .recentlyRead
        filter = .all
        loupeDiameter = 260
        loupeMagnification = 2.5
    }
}
