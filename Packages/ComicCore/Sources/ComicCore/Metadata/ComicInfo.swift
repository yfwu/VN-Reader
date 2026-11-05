import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Minimal ComicInfo.xml (Anansi schema) reader.
public enum ComicInfoParser {
    public static func parse(_ data: Data) -> ComicMetadata? {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() || !delegate.values.isEmpty else { return nil }
        let v = delegate.values
        func s(_ k: String) -> String? {
            guard let t = v[k]?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            return t
        }
        let meta = ComicMetadata(title: s("title"), series: s("series"), number: s("number"), volume: s("volume"),
                                 writer: s("writer"), penciller: s("penciller"), publisher: s("publisher"),
                                 year: s("year").flatMap { Int($0) }, summary: s("summary"),
                                 prefersRightToLeft: s("manga")?.lowercased() == "yesandrighttoleft")
        if meta == ComicMetadata() { return nil }
        return meta
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var values: [String: String] = [:]
        private var stack: [String] = []
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            stack.append(elementName.lowercased())
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            // Only direct children of <ComicInfo>.
            if stack.count == 2, stack[0] == "comicinfo", values[stack[1]] == nil { values[stack[1]] = text }
            stack.removeLast()
            text = ""
        }
    }
}
