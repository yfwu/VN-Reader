import Foundation

/// Pure reading-navigation rules shared by the UI and tests.
///
/// The logical page list is never reversed: page 0 is always the first page of
/// the book. Reading direction only changes how screen positions map to
/// "next" / "previous".
public enum ReaderNavigation {
    public enum TapRegion: Equatable { case left, center, right }
    public enum Action: Equatable { case next, previous, toggleChrome }
    public enum SwipeDirection: Equatable { case fingerMovedLeft, fingerMovedRight }

    /// Width fraction of each side tap zone.
    public static let sideZoneFraction = 0.3

    public static func region(x: Double, width: Double) -> TapRegion {
        guard width > 0 else { return .center }
        let f = x / width
        if f < sideZoneFraction { return .left }
        if f > 1 - sideZoneFraction { return .right }
        return .center
    }

    public static func action(for region: TapRegion, direction: ReadingDirection) -> Action {
        switch (region, direction) {
        case (.center, _): return .toggleChrome
        case (.right, .leftToRight), (.left, .rightToLeft): return .next
        case (.left, .leftToRight), (.right, .rightToLeft): return .previous
        }
    }

    /// LTR: dragging the page leftwards reveals the next page (it sits on the right).
    /// RTL: the next page sits on the left, so dragging rightwards reveals it.
    public static func action(for swipe: SwipeDirection, direction: ReadingDirection) -> Action {
        switch (swipe, direction) {
        case (.fingerMovedLeft, .leftToRight), (.fingerMovedRight, .rightToLeft): return .next
        default: return .previous
        }
    }

    /// Which logical page sits spatially to the right / left of `page`.
    public static func pageOnRight(of page: Int, direction: ReadingDirection) -> Int {
        direction == .leftToRight ? page + 1 : page - 1
    }

    public static func pageOnLeft(of page: Int, direction: ReadingDirection) -> Int {
        direction == .leftToRight ? page - 1 : page + 1
    }

    /// Applies an action; returns nil at the book boundaries.
    public static func apply(_ action: Action, to page: Int, pageCount: Int) -> Int? {
        switch action {
        case .toggleChrome: return page
        case .next: return page + 1 < pageCount ? page + 1 : nil
        case .previous: return page > 0 ? page - 1 : nil
        }
    }

    /// Pages to keep decoded around `page` (current first, then forward bias).
    public static func prefetchOrder(around page: Int, pageCount: Int, ahead: Int = 2, behind: Int = 1) -> [Int] {
        var r = [page]
        for d in 1...max(ahead, behind) {
            if d <= ahead, page + d < pageCount { r.append(page + d) }
            if d <= behind, page - d >= 0 { r.append(page - d) }
        }
        return r.filter { $0 >= 0 && $0 < pageCount }
    }
}

/// Two-page spreads (P1). Spreads hold logical page indices in reading order.
public struct SpreadLayout: Equatable, Sendable {
    public struct Spread: Equatable, Sendable {
        public var pages: [Int]
        /// Left-to-right screen order for this direction (RTL puts the earlier page on the right).
        public func screenOrder(_ direction: ReadingDirection) -> [Int] {
            direction == .leftToRight ? pages : pages.reversed()
        }
    }

    public var spreads: [Spread]

    /// - Parameters:
    ///   - coverAlone: show page 0 by itself.
    ///   - shift: pair offset adjustment (inserts a single page before pairing).
    ///   - widePages: pages that are already spreads (landscape images); always alone.
    public init(pageCount: Int, coverAlone: Bool = true, shift: Bool = false, widePages: Set<Int> = []) {
        var result: [Spread] = []
        var i = 0
        if coverAlone, pageCount > 0 { result.append(Spread(pages: [0])); i = 1 }
        if shift, i < pageCount { result.append(Spread(pages: [i])); i += 1 }
        while i < pageCount {
            if widePages.contains(i) || i + 1 >= pageCount || widePages.contains(i + 1) {
                result.append(Spread(pages: [i]))
                i += 1
            } else {
                result.append(Spread(pages: [i, i + 1]))
                i += 2
            }
        }
        spreads = result
    }

    public func spreadIndex(containing page: Int) -> Int {
        spreads.firstIndex { $0.pages.contains(page) } ?? 0
    }
}
