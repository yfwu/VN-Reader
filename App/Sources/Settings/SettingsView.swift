import SwiftUI
import ComicCore

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var importer: ImportCoordinator
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var usage: (books: Int64, caches: Int64)?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.readingDirection, selection: $settings.defaultDirection) {
                        Text(L10n.directionRTL).tag(ReadingDirection.rightToLeft)
                        Text(L10n.directionLTR).tag(ReadingDirection.leftToRight)
                    }
                    Picker(L10n.fitMode, selection: $settings.defaultFitMode) {
                        Text(L10n.fitPage).tag(PageFitMode.fitPage)
                        Text(L10n.fitWidth).tag(PageFitMode.fitWidth)
                    }
                    Picker(L10n.layout, selection: $settings.defaultLayout) {
                        Text(L10n.layoutSingle).tag(PageLayout.single)
                        Text(L10n.layoutDouble).tag(PageLayout.double)
                        Text(L10n.layoutVertical).tag(PageLayout.vertical)
                    }
                } header: { Text(L10n.settingsDefaults) } footer: { Text(L10n.settingsDefaultsFooter) }

                Section(L10n.settingsReading) {
                    Picker(L10n.background, selection: $settings.background) {
                        ForEach(ReaderBackground.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle(L10n.settingsTapToTurn, isOn: $settings.tapToTurn)
                    Toggle(L10n.settingsAnimate, isOn: $settings.animatePageTurns)
                }

                Section {
                    LabeledContent(L10n.settingsBooksSize, value: usage.map { ErrorMessages.bytes($0.books) } ?? "…")
                    LabeledContent(L10n.settingsCacheSize, value: usage.map { ErrorMessages.bytes($0.caches) } ?? "…")
                    Button(L10n.settingsClearCache, role: .destructive) {
                        library.clearCaches(except: [])
                        CoverCache.shared.purge()
                        Task {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            usage = await library.storageUsage()
                        }
                    }
                } header: { Text(L10n.settingsStorage) } footer: { Text(L10n.settingsCacheFooter) }

                Section(L10n.settingsAbout) {
                    LabeledContent(L10n.settingsVersion, value: appVersion)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.settingsFormats)
                        Text(L10n.settingsFormatsValue).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text(L10n.settingsPrivacy).font(.footnote).foregroundStyle(.secondary)
                    // Closes settings so the new book, or the duplicate notice, is visible.
                    Button(L10n.guideAdd) {
                        UserGuide.add(to: importer)
                        dismiss()
                    }
                    .accessibilityIdentifier("settings.guide")
                    NavigationLink(L10n.settingsLicenses) { LicensesView() }
                }
            }
            .navigationTitle(L10n.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { dismiss() }.accessibilityIdentifier("settings.done")
                }
            }
            .task { usage = await library.storageUsage() }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b)) · unrar \(RarArchive.unrarVersion)"
    }
}

struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: "unRAR source code").font(.headline)
                Text(verbatim: "This app uses the unRAR source code (version \(RarArchive.unrarVersion)) by Alexander Roshal, used under the unRAR license: it may be used in any software to handle RAR archives without limitations free of charge, but cannot be used to develop RAR (WinRAR) compatible archiver and to re-create RAR compression algorithm, which is proprietary.")
                    .font(.footnote)
                Text(verbatim: "zlib").font(.headline)
                Text(verbatim: "Deflate decompression uses the zlib library provided by the operating system (zlib license, © Jean-loup Gailly and Mark Adler).")
                    .font(.footnote)
                Text(verbatim: "See THIRD_PARTY_NOTICES.md in the source repository for full texts.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(L10n.settingsLicenses)
    }
}
