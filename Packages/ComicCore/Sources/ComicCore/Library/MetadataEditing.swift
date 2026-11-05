import Foundation

/// Editable ComicInfo-style fields, in the order the editor shows them.
public enum MetadataField: String, CaseIterable, Sendable {
    case series, number, volume, title, writer, penciller, publisher, year, summary

    /// Fields that differ per book; batch editing leaves them alone.
    public var isPerBook: Bool { self == .summary }
}

extension ComicMetadata {
    /// Text access to every editable field. Setting nil or blank text clears it;
    /// a year that is not a number clears the year.
    public subscript(field: MetadataField) -> String? {
        get {
            switch field {
            case .series: return series
            case .number: return number
            case .volume: return volume
            case .title: return title
            case .writer: return writer
            case .penciller: return penciller
            case .publisher: return publisher
            case .year: return year.map(String.init)
            case .summary: return summary
            }
        }
        set {
            let v = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let t = (v?.isEmpty ?? true) ? nil : v
            switch field {
            case .series: series = t
            case .number: number = t
            case .volume: volume = t
            case .title: title = t
            case .writer: writer = t
            case .penciller: penciller = t
            case .publisher: publisher = t
            case .year: year = t.flatMap { Int($0) }
            case .summary: summary = t
            }
        }
    }
}

/// How a display name is built from metadata.
public enum BookNameStyle: String, CaseIterable, Sendable {
    /// US comics: "Batman (2016) #45" (series, run, issue).
    case seriesIssue
    /// Manga and collected editions: "Series" + the app's localised "volume N" around `number`.
    case seriesVolume
    /// The book's own title.
    case title
}

public enum MetadataEditor {
    /// Builds a display name, or nil when the fields the style needs are empty.
    /// `volumeFormat` wraps the number for `.seriesVolume` (e.g. "第 3 卷").
    public static func displayName(style: BookNameStyle, metadata m: ComicMetadata,
                                   volumeFormat: (String) -> String = { "Vol. \($0)" }) -> String? {
        switch style {
        case .title:
            return m.title
        case .seriesVolume:
            guard let series = m.series else { return nil }
            return m.number.map { series + " " + volumeFormat($0) } ?? series
        case .seriesIssue:
            guard let series = m.series else { return nil }
            var name = series
            if let v = m.volume {
                if v.count == 4, v.allSatisfy(\.isNumber) { name += " (\(v))" }       // start year
                else if v.allSatisfy(\.isNumber) { name += " Vol. \(v)" }
                else { name += " " + v }                                             // "v2", "Vol. 2"
            }
            if let n = m.number { name += " #" + n }
            return name
        }
    }

    /// Sets the given fields on a record; other fields keep their values. An empty
    /// string clears a field. Metadata that ends up empty is removed.
    public static func apply(_ changes: [MetadataField: String], to record: inout BookRecord) {
        guard !changes.isEmpty else { return }
        var m = record.metadata ?? ComicMetadata()
        for (field, value) in changes { m[field] = value }
        record.metadata = m == ComicMetadata() ? nil : m
    }

    /// Issue numbers start, start+1, … in natural order of the original file names,
    /// which is how downloaded issues are normally numbered.
    public static func sequentialNumbers(for records: [BookRecord], start: Int) -> [UUID: String] {
        let ordered = records.sorted {
            let c = NaturalSort.compareNames($0.originalFileName, $1.originalFileName)
            return c != .orderedSame ? c == .orderedAscending : $0.importedAt < $1.importedAt
        }
        var result: [UUID: String] = [:]
        for (i, r) in ordered.enumerated() { result[r.id] = String(start + i) }
        return result
    }

    /// Library order by series: series (or the display name when there is none), run,
    /// number, then display name; all compared naturally ("#2" before "#10").
    public static func seriesOrder(_ a: BookRecord, _ b: BookRecord) -> Bool {
        let keys: [(BookRecord) -> String] = [
            { $0.metadata?.series ?? $0.displayName },
            { $0.metadata?.volume ?? "" },
            { $0.metadata?.number ?? "" },
            { $0.displayName },
        ]
        for key in keys {
            let c = NaturalSort.compareNames(key(a), key(b))
            if c != .orderedSame { return c == .orderedAscending }
        }
        return a.importedAt < b.importedAt
    }
}
