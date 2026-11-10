import SwiftUI
import UniformTypeIdentifiers
import ComicCore

extension UTType {
    static let cbz = UTType(importedAs: "org.yfwu.vnreader.cbz", conformingTo: .data)
    static let cbr = UTType(importedAs: "org.yfwu.vnreader.cbr", conformingTo: .data)
    static let rar = UTType("com.rarlab.rar-archive") ?? UTType(filenameExtension: "rar") ?? .archive

    /// Types offered by the document picker. Content is verified after import,
    /// so the list is generous (other apps may own the .cbz/.cbr extensions).
    static var comicImportTypes: [UTType] {
        var types: [UTType] = [.cbz, .cbr, .zip, .rar, .archive]
        for ext in ["cbz", "cbr"] {
            if let t = UTType(filenameExtension: ext), !types.contains(t) { types.append(t) }
        }
        return types
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var importer: ImportCoordinator
    @ObservedObject private var settings = AppSettings.shared
    @State private var search = ""
    @State private var showPicker = false
    @State private var showSettings = false
    @State private var openBook: BookRecord?
    @State private var renaming: BookRecord?
    @State private var renameText = ""
    @State private var deleting: BookRecord?
    @State private var resetting: BookRecord?
    @State private var dropTargeted = false
    @State private var infoBook: BookRecord?
    @State private var batch: BatchSelection?
    /// nil when not selecting.
    @State private var selection: Set<UUID>?

    private var books: [BookRecord] {
        library.visibleBooks(search: search, sort: settings.sort, filter: settings.filter)
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.books.isEmpty && importer.jobs.isEmpty {
                    emptyLibrary
                } else {
                    libraryContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 20).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
                        .padding(8).allowsHitTesting(false)
                }
            }
            .navigationTitle(selection.map { L10n.selectedCount($0.count) } ?? L10n.libraryTitle)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: L10n.searchPrompt)
            .toolbar { toolbar }
            #if targetEnvironment(macCatalyst)
            // A Catalyst fullScreenCover can leave its presenting window's native
            // navigation toolbar visible. Hide the library bar until reading ends.
            .toolbar(openBook == nil ? .automatic : .hidden, for: .navigationBar)
            #endif
            .fileImporter(isPresented: $showPicker, allowedContentTypes: UTType.comicImportTypes, allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): importer.importFiles(urls, securityScoped: true)
                case .failure(let error): library.notice = ErrorMessages.explain(error).message
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestComicImport)) { _ in
                guard openBook == nil else { return }
                showPicker = true
            }
            .onDrop(of: [.fileURL, .data], isTargeted: $dropTargeted) { providers in
                DropImporter.handle(providers, importer: importer)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $infoBook) { BookInfoView(book: library.book($0.id) ?? $0) }
            .sheet(item: $batch) { BatchInfoView(books: $0.books) { selection = nil } }
            .onChange(of: library.books.isEmpty) { _, empty in if empty { selection = nil } }
            .fullScreenCover(item: $openBook) { book in
                ReaderScreen(record: library.book(book.id) ?? book, library: library)
            }
            .alert(L10n.renameTitle, isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(L10n.renamePlaceholder, text: $renameText).accessibilityIdentifier("rename.field")
                Button(L10n.save) { if let b = renaming { library.rename(b.id, to: renameText) }; renaming = nil }
                Button(L10n.cancel, role: .cancel) { renaming = nil }
            }
            .confirmationDialog(L10n.deleteConfirmTitle(deleting?.displayName ?? ""),
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button(L10n.menuDelete, role: .destructive) { if let b = deleting { library.delete(b.id) }; deleting = nil }
                Button(L10n.cancel, role: .cancel) { deleting = nil }
            } message: {
                Text(L10n.deleteConfirmMessage)
            }
            .confirmationDialog(L10n.resetConfirmTitle,
                                isPresented: Binding(get: { resetting != nil }, set: { if !$0 { resetting = nil } }),
                                titleVisibility: .visible) {
                Button(L10n.menuResetProgress, role: .destructive) { if let b = resetting { library.resetProgress(b.id) }; resetting = nil }
                Button(L10n.cancel, role: .cancel) { resetting = nil }
            }
            .alert(L10n.libraryTitle, isPresented: Binding(get: { library.notice != nil }, set: { if !$0 { library.notice = nil } })) {
                Button(L10n.ok) { library.notice = nil }
            } message: {
                Text(library.notice ?? "")
            }
        }
    }

    /// The item structure stays the same in and out of selection mode (only the
    /// contents change); swapping whole toolbars hides the search drawer.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let selection {
                Button(L10n.menuEditInfo) {
                    batch = BatchSelection(books: library.books.filter { selection.contains($0.id) })
                }
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("library.batchinfo")
                Button(L10n.done) { self.selection = nil }
                    .accessibilityIdentifier("library.select.done")
            } else {
                if !library.books.isEmpty {
                    Button { selection = [] } label: {
                        Label(L10n.select, systemImage: "checkmark.circle")
                    }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel(L10n.select)
                        .help(L10n.select)
                        .accessibilityIdentifier("library.select")
                }
                Menu {
                    Picker(L10n.sortMenu, selection: $settings.sort) {
                        ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(L10n.filterAll, selection: $settings.filter) {
                        ForEach(LibraryFilter.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label(L10n.sortMenu, systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("library.sort")
                Button { showPicker = true } label: {
                    Label(L10n.importButton, systemImage: "plus")
                }
                .accessibilityLabel(L10n.importAccessibility)
                .accessibilityIdentifier("library.import")
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            if let selection {
                let all = !books.isEmpty && books.allSatisfy { selection.contains($0.id) }
                Button(all ? L10n.deselectAll : L10n.selectAll) {
                    self.selection = all ? [] : Set(books.map(\.id))
                }
                .accessibilityIdentifier("library.selectall")
                .keyboardShortcut("a", modifiers: .command)
            } else {
                Button { showSettings = true } label: { Label(L10n.settings, systemImage: "gearshape") }
                    .accessibilityIdentifier("library.settings")
            }
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label(L10n.emptyTitle, systemImage: "books.vertical")
        } description: {
            Text(L10n.emptyMessage)
        } actions: {
            Button { showPicker = true } label: {
                Label(L10n.importButton, systemImage: "square.and.arrow.down")
                    .padding(.horizontal, 8)
                    .frame(minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("library.empty.import")
            Button(L10n.guideAdd) { UserGuide.add(to: importer) }
                .accessibilityIdentifier("library.empty.guide")
        }
        .frame(maxWidth: 520)
    }

    private var libraryContent: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !importer.jobs.isEmpty { ImportJobsSection() }
                    if selection == nil, search.isEmpty, settings.filter == .all, let book = library.continueReading {
                        ContinueReadingCard(book: book) { openBook = book }
                    }
                    if !books.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 20, alignment: .top)],
                                  alignment: .leading, spacing: 28) {
                            ForEach(books) { book in
                                BookCell(book: book,
                                         open: {
                                             if selection == nil { openBook = book }
                                             else if selection!.contains(book.id) { selection!.remove(book.id) }
                                             else { selection!.insert(book.id) }
                                         },
                                         readFromStart: {
                                             library.resetProgress(book.id)
                                             openBook = library.book(book.id)
                                         },
                                         rename: { renameText = book.displayName; renaming = book },
                                         editInfo: { infoBook = book },
                                         reset: { resetting = book },
                                         delete: { deleting = book },
                                         selected: selection.map { $0.contains(book.id) })
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        .overlay {
            if books.isEmpty && importer.jobs.isEmpty {
                Group {
                    if search.isEmpty {
                        ContentUnavailableView(L10n.noResultsTitle, systemImage: "line.3.horizontal.decrease.circle")
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Imports files dropped onto the library (P1: drag and drop).
enum DropImporter {
    @MainActor
    static func handle(_ providers: [NSItemProvider], importer: ImportCoordinator) -> Bool {
        var accepted = false
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            accepted = true
            // Read on this thread; the completion handler only captures the String.
            let suggestedName = p.suggestedName
            _ = p.loadFileRepresentation(forTypeIdentifier: UTType.data.identifier) { url, _ in
                guard let url else { return }
                // The provided file is deleted when this block returns: copy it first.
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Dropped/\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                var name = url.lastPathComponent
                if let suggested = suggestedName, !suggested.isEmpty {
                    name = (suggested as NSString).pathExtension.isEmpty && !url.pathExtension.isEmpty
                        ? suggested + "." + url.pathExtension : suggested
                }
                // Only a bare file name from another app; never a path.
                name = (name as NSString).lastPathComponent
                if name.isEmpty || name == "." || name == ".." { name = url.lastPathComponent }
                let dest = dir.appendingPathComponent(name)
                guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return }
                onMain { importer.importFiles([dest], securityScoped: false, deleteAfterImport: true) }
            }
        }
        return accepted
    }
}
