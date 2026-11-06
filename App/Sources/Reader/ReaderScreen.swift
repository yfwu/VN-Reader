import SwiftUI
import ComicCore

struct ReaderPagerView: UIViewControllerRepresentable {
    let model: ReaderViewModel
    func makeUIViewController(context: Context) -> ReaderViewController { ReaderViewController(model: model) }
    func updateUIViewController(_ vc: ReaderViewController, context: Context) {}
}

struct VerticalReaderView: UIViewControllerRepresentable {
    let model: ReaderViewModel
    func makeUIViewController(context: Context) -> VerticalReaderController { VerticalReaderController(model: model) }
    func updateUIViewController(_ vc: VerticalReaderController, context: Context) {}
}

/// Full-screen reader: UIKit pager + SwiftUI toolbars and sheets.
struct ReaderScreen: View {
    @StateObject private var model: ReaderViewModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showThumbnails = false
    @State private var showSettings = false
    @State private var showJump = false
    @State private var jumpText = ""
    @State private var scrubPage: Double?
    @State private var sliderFrame: CGRect = .zero

    init(record: BookRecord, library: LibraryStore) {
        _model = StateObject(wrappedValue: ReaderViewModel(record: record, library: library))
    }

    var body: some View {
        ZStack {
            Color(settings.background.uiColor).ignoresSafeArea()
            if let err = model.openError {
                openErrorView(err)
            } else if model.isReady {
                if model.record.layout == .vertical {
                    VerticalReaderView(model: model).ignoresSafeArea()
                } else {
                    ReaderPagerView(model: model).ignoresSafeArea()
                }
            } else {
                ProgressView().controlSize(.large)
            }
            if model.isReady, needsPreparationOverlay {
                preparationOverlay
            }
            if model.isReady, model.loupeVisible {
                LoupeOverlay(model: model).ignoresSafeArea().transition(.opacity)
            }
            if model.chromeVisible || model.openError != nil {
                chrome.transition(.opacity)
            }
            if let t = model.toast {
                Text(t)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("reader.toast")
            }
        }
        .statusBarHidden(!model.chromeVisible)
        .persistentSystemOverlays(model.chromeVisible ? .automatic : .hidden)
        .onAppear { model.open() }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.flush() }
        }
        .sheet(isPresented: $showThumbnails) {
            ThumbnailSheet(model: model) { page in
                showThumbnails = false
                model.jump(to: page)
            }
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(model: model)
        }
        .alert(L10n.jumpToPage, isPresented: $showJump) {
            TextField(L10n.jumpRange(model.pageCount), text: $jumpText)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("reader.jump.field")
            Button(L10n.go) {
                if let n = Int(jumpText.trimmingCharacters(in: .whitespaces)) { model.jump(to: n - 1) }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.jumpPrompt + "（" + L10n.jumpRange(model.pageCount) + "）")
        }
    }

    private var needsPreparationOverlay: Bool {
        if case .running = model.preparation { return !model.isCurrentPageReady }
        if case .failed = model.preparation { return !model.isCurrentPageReady }
        return false
    }

    // MARK: Overlays

    private var preparationOverlay: some View {
        VStack(spacing: 14) {
            switch model.preparation {
            case .running(let done, let total):
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .frame(width: 220)
                Text(L10n.preparingTitle).font(.headline)
                Text(L10n.preparingProgress(done, total))
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .failed(let e):
                let x = ErrorMessages.explain(e)
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text(x.title).font(.headline)
                Text(x.message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            default:
                EmptyView()
            }
            Button(L10n.backToLibrary) { dismiss() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reader.preparing.cancel")
        }
        .padding(24)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding()
        .accessibilityIdentifier("reader.preparing")
    }

    private func openErrorView(_ err: ErrorExplanation) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(L10n.openFailed).font(.headline)
            Text(err.title).font(.subheadline.weight(.semibold))
            Text(err.message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: Toolbars

    private var chrome: some View {
        VStack(spacing: 0) {
            topBar
            // Not a Spacer: that has no width, and the preview needs the whole screen's.
            Color.clear
                .overlay(alignment: .bottom) {
                    if let scrubPage {
                        PageScrubPreview(model: model, page: Int(scrubPage), thumbX: thumbX(scrubPage))
                            .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
                    }
                }
                .allowsHitTesting(false)
            if model.isReady && model.openError == nil { bottomBar }
        }
        .coordinateSpace(.named(Self.chromeSpace))
    }

    private static let chromeSpace = "reader.chrome"

    /// Where the slider's thumb sits for `page`. The thumb stops short of the track's ends.
    private func thumbX(_ page: Double) -> CGFloat {
        let inset: CGFloat = 16
        let fraction = page / Double(max(model.pageCount - 1, 1))
        let along = model.record.readingDirection == .rightToLeft ? 1 - fraction : fraction
        return sliderFrame.minX + inset + (sliderFrame.width - inset * 2) * along
    }

    private var topBar: some View {
        HStack(spacing: 4) {
            Button { dismiss() } label: {
                Label(L10n.backToLibrary, systemImage: "chevron.backward")
                    .labelStyle(.titleAndIcon)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("reader.back")
            Spacer(minLength: 8)
            Text(model.record.displayName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if model.isReady && model.openError == nil {
                iconButton("number", label: L10n.jumpToPage, id: "reader.goto") { askForPage() }
                iconButton(model.isBookmarked ? "bookmark.fill" : "bookmark",
                           label: model.isBookmarked ? L10n.removeBookmark : L10n.addBookmark, id: "reader.bookmark") {
                    model.toggleBookmark()
                }
                iconButton("slider.horizontal.3", label: L10n.readerSettings, id: "reader.settings") { showSettings = true }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private var bottomBar: some View {
        let count = model.pageCount
        let displayed = Int(scrubPage ?? Double(model.currentPage))
        return HStack(spacing: 12) {
            iconButton("square.grid.3x3", label: L10n.thumbnails, id: "reader.thumbnails") { showThumbnails = true }
            if count > 1 {
                Slider(value: Binding(get: { scrubPage ?? Double(model.currentPage) },
                                      set: { scrubPage = $0.rounded() }),
                       in: 0...Double(count - 1), step: 1, onEditingChanged: { editing in
                    if editing {
                        withAnimation(.easeOut(duration: 0.16)) { scrubPage = Double(model.currentPage) }
                    } else if let p = scrubPage {
                        model.jump(to: Int(p))
                        withAnimation(.easeIn(duration: 0.14)) { scrubPage = nil }
                    }
                })
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.chromeSpace)) } action: { sliderFrame = $0 }
                // RTL books: page 1 is on the right end of the slider.
                .environment(\.layoutDirection, model.record.readingDirection == .rightToLeft ? .rightToLeft : .leftToRight)
                .accessibilityLabel(L10n.pageSlider)
                .accessibilityValue(L10n.pageA11y(displayed + 1, count))
                .accessibilityIdentifier("reader.slider")
            } else {
                Spacer()
            }
            Button(action: askForPage) {
                Text(L10n.pageIndicator(displayed + 1, count))
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 72, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.jumpToPage)
            .accessibilityValue(L10n.pageA11y(displayed + 1, count))
            .accessibilityIdentifier("reader.jump")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func askForPage() {
        jumpText = ""
        showJump = true
    }

    private func iconButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Thumbnails & bookmarks

struct ThumbnailSheet: View {
    @ObservedObject var model: ReaderViewModel
    let onSelect: (Int) -> Void
    @State private var tab = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(L10n.thumbnails, selection: $tab) {
                    Text(L10n.allPages).tag(0)
                    Text(L10n.bookmarks).tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                if tab == 0 {
                    grid(Array(0..<model.pageCount))
                } else if model.record.bookmarks.isEmpty {
                    ContentUnavailableView(L10n.bookmarks, systemImage: "bookmark", description: Text(L10n.noBookmarks))
                } else {
                    grid(model.record.bookmarks.filter { $0 < model.pageCount })
                }
            }
            .navigationTitle(L10n.thumbnails)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { dismiss() }.accessibilityIdentifier("thumbnails.done")
                }
            }
        }
    }

    private func grid(_ pages: [Int]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 12)], spacing: 16) {
                    ForEach(pages, id: \.self) { p in
                        ThumbnailCell(model: model, page: p, isCurrent: model.visiblePages.contains(p))
                            .id(p)
                            .onTapGesture { onSelect(p) }
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .environment(\.layoutDirection, model.record.readingDirection == .rightToLeft ? .rightToLeft : .leftToRight)
            }
            .onAppear { proxy.scrollTo(model.currentPage, anchor: .center) }
        }
    }
}

struct ThumbnailCell: View {
    @ObservedObject var model: ReaderViewModel
    let page: Int
    let isCurrent: Bool
    @State private var image: UIImage?
    @State private var attempted = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15))
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if attempted {
                    Image(systemName: "hourglass").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .aspectRatio(0.7, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isCurrent ? Color.accentColor : .clear, lineWidth: 3))
            HStack(spacing: 2) {
                if model.record.bookmarks.contains(page) { Image(systemName: "bookmark.fill").font(.caption2) }
                Text(verbatim: "\(page + 1)").font(.caption.monospacedDigit())
            }
            .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.pageNumber(page + 1))
        .accessibilityIdentifier("thumb.\(page)")
        .task(id: model.preparation) {
            guard image == nil, let t = model.thumbnails else { return }
            if let c = t.cached(page) { image = c; return }
            image = await t.thumbnail(page)
            attempted = true
        }
    }
}

// MARK: - Reader settings

struct ReaderSettingsSheet: View {
    @ObservedObject var model: ReaderViewModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.readingDirection) {
                    Picker(L10n.readingDirection, selection: Binding(get: { model.record.readingDirection },
                                                                     set: { model.setDirection($0) })) {
                        Text(L10n.directionRTL).tag(ReadingDirection.rightToLeft)
                        Text(L10n.directionLTR).tag(ReadingDirection.leftToRight)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("settings.direction")
                }
                Section(L10n.fitMode) {
                    Picker(L10n.fitMode, selection: Binding(get: { model.record.fitMode }, set: { model.setFitMode($0) })) {
                        Text(L10n.fitPage).tag(PageFitMode.fitPage)
                        Text(L10n.fitWidth).tag(PageFitMode.fitWidth)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.fit")
                }
                Section(L10n.layout) {
                    Picker(L10n.layout, selection: Binding(get: { model.record.layout }, set: { model.setLayout($0) })) {
                        Text(L10n.layoutSingle).tag(PageLayout.single)
                        Text(L10n.layoutDouble).tag(PageLayout.double)
                        Text(L10n.layoutVertical).tag(PageLayout.vertical)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.layout")
                    if model.record.layout == .double {
                        Toggle(L10n.coverAlone, isOn: Binding(get: { settings.coverAlone },
                                                              set: { settings.coverAlone = $0; model.appSettingsChanged() }))
                        Toggle(L10n.shiftSpread, isOn: Binding(get: { settings.shiftSpreads },
                                                               set: { settings.shiftSpreads = $0; model.appSettingsChanged() }))
                    }
                }
                Section(L10n.background) {
                    Picker(L10n.background, selection: Binding(get: { settings.background },
                                                               set: { settings.background = $0; model.appSettingsChanged() })) {
                        ForEach(ReaderBackground.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle(L10n.settingsTapToTurn, isOn: $settings.tapToTurn)
                    Toggle(L10n.settingsAnimate, isOn: $settings.animatePageTurns)
                }
            }
            .navigationTitle(L10n.readerSettings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { dismiss() }.accessibilityIdentifier("readersettings.done")
                }
            }
        }
    }
}
