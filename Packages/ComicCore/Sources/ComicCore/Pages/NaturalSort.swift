import Foundation

/// Reproducible, locale-independent natural ordering for page paths.
///
/// Rules (see docs/PAGE_ORDERING.md):
/// 1. Paths are compared component by component.
/// 2. At the first differing level, a file sorts before a sub-directory.
/// 3. Names are NFKC-normalised (full-width digits become ASCII) and compared
///    case-insensitively; the stem is compared before the extension.
/// 4. Runs of digits compare by numeric value ("2" < "10", "002" == "2").
/// 5. Ties are broken by fewer leading zeros, then by exact Unicode scalars,
///    and finally by the entry's position in the archive.
public enum NaturalSort {
    enum Token: Equatable {
        case number(digits: String, leadingZeros: Int)  // digits without leading zeros ("" for 0)
        case text([Unicode.Scalar])
    }

    static func normalize(_ s: String) -> String {
        s.precomposedStringWithCompatibilityMapping.lowercased()
    }

    static func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        var digits = ""
        var text: [Unicode.Scalar] = []
        func flushDigits() {
            guard !digits.isEmpty else { return }
            let trimmed = digits.drop(while: { $0 == "0" })
            tokens.append(.number(digits: String(trimmed), leadingZeros: digits.count - trimmed.count))
            digits = ""
        }
        func flushText() {
            guard !text.isEmpty else { return }
            tokens.append(.text(text))
            text = []
        }
        for u in s.unicodeScalars {
            if u.value >= 0x30 && u.value <= 0x39 {
                flushText()
                digits.unicodeScalars.append(u)
            } else {
                flushDigits()
                text.append(u)
            }
        }
        flushDigits()
        flushText()
        return tokens
    }

    /// Compares two single names (no '/').
    public static func compareNames(_ a: String, _ b: String) -> ComparisonResult {
        let (sa, ea) = splitExtension(normalize(a))
        let (sb, eb) = splitExtension(normalize(b))
        let r = compareTokens(tokenize(sa), tokenize(sb))
        if r != .orderedSame { return r }
        let re = compareTokens(tokenize(ea), tokenize(eb))
        if re != .orderedSame { return re }
        // Tie breakers: leading zeros, then raw scalars of the original.
        let za = leadingZeroSignature(tokenize(sa)), zb = leadingZeroSignature(tokenize(sb))
        if za != zb { return za.lexicographicallyPrecedes(zb) ? .orderedAscending : .orderedDescending }
        return compareScalars(Array(a.unicodeScalars), Array(b.unicodeScalars))
    }

    /// Compares full archive paths ('/' separated).
    public static func comparePaths(_ a: String, _ b: String) -> ComparisonResult {
        let ca = components(a), cb = components(b)
        var i = 0
        while i < ca.count && i < cb.count {
            let aIsFile = i == ca.count - 1, bIsFile = i == cb.count - 1
            if aIsFile != bIsFile { return aIsFile ? .orderedAscending : .orderedDescending }
            let r = compareNames(ca[i], cb[i])
            if r != .orderedSame { return r }
            i += 1
        }
        if ca.count != cb.count { return ca.count < cb.count ? .orderedAscending : .orderedDescending }
        return compareScalars(Array(a.unicodeScalars), Array(b.unicodeScalars))
    }

    static func components(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    static func splitExtension(_ name: String) -> (String, String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]))
    }

    static func leadingZeroSignature(_ tokens: [Token]) -> [Int] {
        tokens.compactMap { if case .number(_, let z) = $0 { return z } else { return nil } }
    }

    static func compareTokens(_ a: [Token], _ b: [Token]) -> ComparisonResult {
        var i = 0
        while i < a.count && i < b.count {
            switch (a[i], b[i]) {
            case let (.number(da, _), .number(db, _)):
                if da.count != db.count { return da.count < db.count ? .orderedAscending : .orderedDescending }
                if da != db { return da < db ? .orderedAscending : .orderedDescending }
            case (.number, .text):
                return .orderedAscending
            case (.text, .number):
                return .orderedDescending
            case let (.text(ta), .text(tb)):
                let r = compareScalars(ta, tb)
                if r != .orderedSame { return r }
            }
            i += 1
        }
        if a.count != b.count { return a.count < b.count ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    static func compareScalars(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> ComparisonResult {
        for (x, y) in zip(a, b) where x != y {
            return x.value < y.value ? .orderedAscending : .orderedDescending
        }
        if a.count == b.count { return .orderedSame }
        return a.count < b.count ? .orderedAscending : .orderedDescending
    }
}
