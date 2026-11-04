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

    private var books: [BookRecord] {
        library.visibleBooks(search: search, sort: settings.sort, filter: settings.filter)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !importer.jobs.isEmpty { ImportJobsSection() }
                    if search.isEmpty, settings.filter == .all, let book = library.continueReading {
                        ContinueReadingCard(book: book) { openBook = book }
                    }
                    if !books.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 20, alignment: .top)],
                                  alignment: .leading, spacing: 28) {
                            ForEach(books) { book in
                                BookCell(book: book,
                                         open: { openBook = book },
                                         readFromStart: {
                                             library.resetProgress(book.id)
                                             openBook = library.book(book.id)
                                         },
                                         rename: { renameText = book.displayName; renaming = book },
                                         reset: { resetting = book },
                                         delete: { deleting = book })
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .overlay { emptyState }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 20).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
                        .padding(8).allowsHitTesting(false)
                }
            }
            .navigationTitle(L10n.libraryTitle)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: L10n.searchPrompt)
            .toolbar { toolbar }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: UTType.comicImportTypes, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { importer.importFiles(urls, securityScoped: true) }
            }
            .onDrop(of: [.fileURL, .data], isTargeted: $dropTargeted) { providers in
                DropImporter.handle(providers, importer: importer)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
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
        }
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: { Label(L10n.settings, systemImage: "gearshape") }
                .accessibilityIdentifier("library.settings")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if library.books.isEmpty && importer.jobs.isEmpty {
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
            }
        } else if books.isEmpty && !library.books.isEmpty {
            ContentUnavailableView.search(text: search)
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
            _ = p.loadFileRepresentation(forTypeIdentifier: UTType.data.identifier) { url, _ in
                guard let url else { return }
                // The provided file is deleted when this block returns: copy it first.
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Dropped/\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                var name = url.lastPathComponent
                if let suggested = p.suggestedName, !suggested.isEmpty {
                    name = (suggested as NSString).pathExtension.isEmpty && !url.pathExtension.isEmpty
                        ? suggested + "." + url.pathExtension : suggested
                }
                let dest = dir.appendingPathComponent(name)
                guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return }
                onMain { importer.importFiles([dest], securityScoped: false, deleteAfterImport: true) }
            }
        }
        return accepted
    }
}
