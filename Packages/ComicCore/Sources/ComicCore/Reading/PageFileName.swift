import Foundation

/// The file name a page gets when it leaves the app, such as "Batman #45 p007.jpg".
public enum PageFileName {
    /// File systems allow 255 bytes; this leaves room for the page number and extension.
    static let maxBookNameBytes = 200

    /// - Parameter page: zero-based, as everywhere else; the name shows it counted from 1.
    public static func make(book: String, page: Int, pageCount: Int, fileExtension: String) -> String {
        let width = String(max(pageCount, 1)).count
        let number = String(repeating: "0", count: max(0, width - String(page + 1).count)) + String(page + 1)
        let name = cleaned(book)
        return (name.isEmpty ? "p\(number)" : "\(name) p\(number)") + ".\(fileExtension)"
    }

    /// Display names are free text: drop what a path cannot hold or would hide the file.
    private static func cleaned(_ book: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        let parts = book.unicodeScalars.split { unsafe.contains($0) || CharacterSet.whitespaces.contains($0) }
        var name = parts.map { String(String.UnicodeScalarView($0)) }.joined(separator: " ")
        while name.hasPrefix(".") || name.hasPrefix(" ") { name.removeFirst() }
        while name.utf8.count > maxBookNameBytes { name.removeLast() }
        while name.hasSuffix(" ") { name.removeLast() }
        return name
    }
}
