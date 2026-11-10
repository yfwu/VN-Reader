import SwiftUI
import ComicCore

extension MetadataField {
    var label: String {
        switch self {
        case .series: return L10n.fieldSeries
        case .number: return L10n.fieldNumber
        case .volume: return L10n.fieldVolume
        case .title: return L10n.fieldTitle
        case .writer: return L10n.fieldWriter
        case .penciller: return L10n.fieldPenciller
        case .publisher: return L10n.fieldPublisher
        case .year: return L10n.fieldYear
        case .summary: return L10n.fieldSummary
        }
    }

    var hint: String {
        switch self {
        case .series: return L10n.hintSeries
        case .number: return L10n.hintNumber
        case .volume: return L10n.hintVolume
        case .title: return L10n.hintTitle
        default: return L10n.hintOptional
        }
    }
}

extension BookNameStyle {
    var title: String {
        switch self {
        case .seriesIssue: return L10n.nameStyleSeriesIssue
        case .seriesVolume: return L10n.nameStyleSeriesVolume
        case .title: return L10n.nameStyleTitle
        }
    }
}

/// One labelled text field of the info editors. Text is kept raw while typing
/// (spaces included) and only normalised when saved.
struct MetadataFieldRow<Trailing: View>: View {
    let field: MetadataField
    @Binding var text: String
    var prompt: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if field == .summary {
            VStack(alignment: .leading, spacing: 6) {
                Text(field.label).font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .top) { input.lineLimit(3...10); trailing }
            }
        } else {
            HStack {
                Text(field.label).frame(minWidth: 72, alignment: .leading)
                input
                trailing
            }
        }
    }

    private var input: some View {
        TextField(field.label, text: $text, prompt: Text(prompt), axis: field == .summary ? .vertical : .horizontal)
            .keyboardType(field == .year ? .numberPad : (field == .number || field == .volume ? .numbersAndPunctuation : .default))
            .textInputAutocapitalization(field == .summary ? .sentences : .words)
            .autocorrectionDisabled(field != .summary)
            .accessibilityIdentifier("info.field.\(field.rawValue)")
    }
}

extension MetadataFieldRow where Trailing == EmptyView {
    init(field: MetadataField, text: Binding<String>, prompt: String) {
        self.init(field: field, text: text, prompt: prompt) { EmptyView() }
    }
}

/// Edits one book's display name and details.
struct BookInfoView: View {
    let book: BookRecord
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var texts: [MetadataField: String]

    init(book: BookRecord) {
        self.book = book
        _name = State(initialValue: book.displayName)
        let m = book.metadata ?? ComicMetadata()
        _texts = State(initialValue: Dictionary(uniqueKeysWithValues: MetadataField.allCases.map { ($0, m[$0] ?? "") }))
    }

    private var edited: ComicMetadata {
        var m = book.metadata ?? ComicMetadata()
        for f in MetadataField.allCases { m[f] = texts[f] }
        return m
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.renamePlaceholder, text: $name)
                        .accessibilityIdentifier("info.name")
                    Menu {
                        ForEach(BookNameStyle.allCases, id: \.self) { style in
                            let generated = LibraryStore.generatedName(style, edited)
                            Button(style.title) { if let generated { name = generated } }
                                .disabled(generated == nil)
                        }
                    } label: {
                        Label(L10n.generateName, systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("info.generate")
                } header: {
                    Text(L10n.renamePlaceholder)
                } footer: {
                    Text(L10n.originalFile(book.originalFileName))
                }

                Section {
                    ForEach(MetadataField.allCases, id: \.self) { f in
                        MetadataFieldRow(field: f, text: binding(f), prompt: f.hint)
                    }
                } header: {
                    Text(L10n.infoDetails)
                } footer: {
                    Text(L10n.infoFooter)
                }
            }
            .navigationTitle(L10n.menuInfo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) {
                        let changes = Dictionary(uniqueKeysWithValues: MetadataField.allCases.compactMap { field -> (MetadataField, String)? in
                            let value = texts[field] ?? ""
                            return value == (book.metadata?[field] ?? "") ? nil : (field, value)
                        })
                        library.saveInfoChanges(book.id, displayName: name == book.displayName ? nil : name, changes: changes)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("info.save")
                }
            }
        }
    }

    private func binding(_ f: MetadataField) -> Binding<String> {
        Binding(get: { texts[f] ?? "" }, set: { texts[f] = $0 })
    }
}

/// Selection handed to the batch editor.
struct BatchSelection: Identifiable {
    let id = UUID()
    let books: [BookRecord]
}

/// Edits shared details of several books at once. Only fields the user touches are
/// applied; fields whose values differ between the books start empty ("multiple values").
struct BatchInfoView: View {
    let books: [BookRecord]
    var onSave: () -> Void = {}
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    private let initial: [MetadataField: String]
    private let mixed: Set<MetadataField>
    @State private var texts: [MetadataField: String]
    @State private var edited: Set<MetadataField> = []
    @State private var autoNumber = false
    @State private var numberStart = 1
    @State private var nameStyle: BookNameStyle?

    private static let fields = MetadataField.allCases.filter { !$0.isPerBook }

    init(books: [BookRecord], onSave: @escaping () -> Void = {}) {
        self.books = books
        self.onSave = onSave
        var initial: [MetadataField: String] = [:]
        var mixed: Set<MetadataField> = []
        for f in Self.fields {
            let values = Set(books.map { $0.metadata?[f] ?? "" })
            if values.count == 1 { initial[f] = values.first } else { initial[f] = ""; mixed.insert(f) }
        }
        self.initial = initial
        self.mixed = mixed
        _texts = State(initialValue: initial)
    }

    private var changes: [MetadataField: String] {
        var c: [MetadataField: String] = [:]
        for f in edited where !(autoNumber && f == .number) { c[f] = texts[f] ?? "" }
        return c
    }

    private var hasChanges: Bool { !changes.isEmpty || autoNumber || nameStyle != nil }

    /// The resulting name of the first book in file-name order.
    private var example: String? {
        guard let style = nameStyle else { return nil }
        let numbers = MetadataEditor.sequentialNumbers(for: books, start: numberStart)
        guard var first = books.first(where: { numbers[$0.id] == String(numberStart) }) else { return nil }
        var c = changes
        if autoNumber { c[.number] = String(numberStart) }
        MetadataEditor.apply(c, to: &first)
        return LibraryStore.generatedName(style, first.metadata) ?? first.displayName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Self.fields.filter { $0 != .number }, id: \.self) { f in row(f) }
                } header: {
                    Text(L10n.infoDetails)
                } footer: {
                    Text(L10n.batchFooter)
                }

                Section {
                    Toggle(L10n.autoNumber, isOn: $autoNumber)
                        .accessibilityIdentifier("info.autonumber")
                    if autoNumber {
                        Stepper(L10n.numberStart(numberStart), value: $numberStart, in: 0...9999)
                    } else {
                        row(.number)
                    }
                } header: {
                    Text(L10n.fieldNumber)
                }

                Section {
                    Picker(L10n.renamePlaceholder, selection: $nameStyle) {
                        Text(L10n.keepUnchanged).tag(BookNameStyle?.none)
                        ForEach(BookNameStyle.allCases, id: \.self) { style in
                            Text(style.title).tag(Optional(style))
                        }
                    }
                    .accessibilityIdentifier("info.namestyle")
                } footer: {
                    if let example { Text(L10n.exampleName(example)) }
                }

                Section {
                } footer: {
                    Text(L10n.infoFooter)
                }
            }
            .navigationTitle(L10n.batchTitle(books.count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) {
                        library.batchEdit(Set(books.map(\.id)), changes: changes,
                                          numberFrom: autoNumber ? numberStart : nil, nameStyle: nameStyle)
                        onSave()
                        dismiss()
                    }
                    .disabled(!hasChanges)
                    .accessibilityIdentifier("info.save")
                }
            }
        }
    }

    private func row(_ f: MetadataField) -> some View {
        MetadataFieldRow(field: f, text: Binding(get: { texts[f] ?? "" }, set: {
                             guard $0 != texts[f] else { return }
                             texts[f] = $0
                             edited.insert(f)
                         }),
                         prompt: mixed.contains(f) && !edited.contains(f) ? L10n.multipleValues : f.hint) {
            if edited.contains(f) {
                Button {
                    texts[f] = initial[f]
                    edited.remove(f)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.revertField)
            }
        }
    }
}
