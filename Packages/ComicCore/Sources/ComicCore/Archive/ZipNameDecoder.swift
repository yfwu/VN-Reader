import Foundation

/// Decodes ZIP entry names that are not flagged as UTF-8.
///
/// Many CJK archives store names in a legacy code page without setting the
/// UTF-8 flag. All names of an archive are decoded with the same encoding,
/// chosen by scoring each candidate on the whole set of names.
enum ZipNameDecoder {
    static var candidates: [String.Encoding] {
        var list: [String.Encoding] = [.utf8, .shiftJIS]
        list.append(contentsOf: cfEncodings)
        list.append(.windowsCP1252)
        list.append(.isoLatin1) // always decodes
        return list
    }

    // Big5 and GB18030 are only reachable through CoreFoundation on Apple platforms.
    private static var cfEncodings: [String.Encoding] {
        #if canImport(Darwin)
        let big5 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue))
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return [String.Encoding(rawValue: big5), String.Encoding(rawValue: gb)]
        #else
        return []
        #endif
    }

    static func chooseEncoding(for rawNames: [Data]) -> String.Encoding {
        let nonASCII = rawNames.filter { $0.contains(where: { $0 >= 0x80 }) }
        if nonASCII.isEmpty { return .utf8 }
        var best: (String.Encoding, Int)? = nil
        for enc in candidates {
            var total = 0
            var ok = true
            for raw in nonASCII {
                guard let s = String(data: raw, encoding: enc) else { ok = false; break }
                total += score(s)
            }
            guard ok else { continue }
            // Valid UTF-8 for every name is a very strong signal.
            if enc == .utf8 { return .utf8 }
            if best == nil || total > best!.1 { best = (enc, total) }
        }
        return best?.0 ?? .isoLatin1
    }

    static func score(_ s: String) -> Int {
        var score = 0
        for u in s.unicodeScalars {
            switch u.value {
            case 0x20...0x7E: score += 1
            case 0x3040...0x30FF: score += 3          // Hiragana / Katakana
            case 0x4E00...0x9FFF: score += 2          // CJK unified ideographs
            case 0x3000...0x303F, 0xFF01...0xFF5E: score += 1 // CJK punctuation / fullwidth forms
            case 0xFF61...0xFF9F: score -= 2          // half-width katakana: usually a mis-decode
            case 0xE000...0xF8FF, 0xFFFD: score -= 6  // private use / replacement
            case 0x00...0x1F, 0x7F...0x9F: score -= 6 // control characters
            case 0xA0...0x24F: score -= 1             // Latin-1 accents: plausible but unlikely in CJK sets
            default: break
            }
        }
        return score
    }
}
