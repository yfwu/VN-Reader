import SwiftUI
import UIKit
import ComicCore

extension Notification.Name {
    static let requestComicImport = Notification.Name("VNReader.requestComicImport")
}

#if targetEnvironment(macCatalyst)
/// Catalyst uses UIKit's menu builder; SwiftUI scene commands do not replace
/// the otherwise disabled native Open item in this reader's window.
final class CatalystApplicationDelegate: UIResponder, UIApplicationDelegate {
    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }
        let importCommand = UIKeyCommand(title: L10n.importButton,
                                         action: #selector(importComics(_:)),
                                         input: "o", modifierFlags: .command)
        let importMenu = UIMenu(title: "", identifier: .open, options: .displayInline,
                               children: [importCommand])
        builder.replace(menu: .open, with: importMenu)
        builder.remove(menu: .openRecent)
    }

    @objc private func importComics(_ sender: UIKeyCommand) {
        NotificationCenter.default.post(name: .requestComicImport, object: nil)
    }
}
#endif

@main
struct VNReaderApp: App {
    #if targetEnvironment(macCatalyst)
    @UIApplicationDelegateAdaptor(CatalystApplicationDelegate.self) private var applicationDelegate
    #endif
    @StateObject private var library: LibraryStore
    @StateObject private var importer: ImportCoordinator
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if CloudSyncEnvironment.smokeRunID == nil { UITestSupport.prepareEnvironment() }
        let paths: LibraryPaths
        do { paths = CloudSyncEnvironment.paths(from: try LibraryPaths.standard()) } catch {
            fatalError("Application Support is unavailable: \(error)")
        }
        let lib = LibraryStore(paths: paths)
        _library = StateObject(wrappedValue: lib)
        _importer = StateObject(wrappedValue: ImportCoordinator(library: lib))
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(importer)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { library.cloudSync.requestAutomaticSync(.appActive) }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Catalyst window ScenePhase can stay active across Command-Tab.
                    library.cloudSync.requestAutomaticSync(.appActive)
                }
                .onOpenURL { url in
                    // Files from "Open in…", AirDrop or the share sheet are copied
                    // into our Inbox by the system; import and remove that copy.
                    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    let inbox = documents.map { ImportSourceOwnership.isAppInboxFile(url, documentsDirectory: $0) } ?? false
                    importer.importFiles([url], securityScoped: !inbox, deleteAfterImport: inbox)
                }
                .task {
                    UITestSupport.seedIfRequested(library: library, importer: importer)
                    if CloudSyncEnvironment.seedBundledGuide, library.books.isEmpty { UserGuide.add(to: importer) }
                    if CloudSyncEnvironment.smokeRunID == nil { UserGuide.addOnFirstLaunch(library: library, importer: importer) }
                    if CloudSyncEnvironment.automaticallyEnable { library.cloudSync.setEnabled(true) }
                    else { library.cloudSync.startIfEnabled() }
                }
        }
    }
}
