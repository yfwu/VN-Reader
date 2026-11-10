import UIKit
import ComicCore

struct CheckFailure: Error { let label: String }
@MainActor var checkCount = 0
@MainActor func check(_ value: @autoclosure () -> Bool, _ label: String) throws {
    guard value() else { throw CheckFailure(label: label) }
    checkCount += 1
    FileHandle.standardOutput.write(Data("PASS: \(label)\n".utf8))
}
@MainActor func settle() async { try? await Task.sleep(nanoseconds: 50_000_000) }

@main final class AuditApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Audit", sessionRole: session.role)
        config.delegateClass = AuditScene.self
        return config
    }

    @MainActor func run(scene: UIWindowScene) async throws {
        let model = ReaderViewModel()
        let reader = ReaderViewController(model: model)
        // UIKit is real; the window remains hidden, so the audit does not take focus.
        window = UIWindow(windowScene: scene)
        window?.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        window?.rootViewController = reader
        reader.loadViewIfNeeded()
        window?.addSubview(reader.view) // Attach coordinates without presenting the native window.
        guard reader.view.window != nil else { throw CheckFailure(label: "hidden window coordinate setup failed") }
        reader.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        reader.viewDidLayoutSubviews()
        try check(reader.units == [[0, 1], [2, 3], [4, 5]], "initial Mac layout pairs portrait pages")
        reader.go(toPage: 3, animated: false, userInitiated: true)
        try check(model.currentPage == 3, "jump keeps the requested logical page inside a pair")
        reader.view.frame.size = CGSize(width: 600, height: 900)
        reader.viewDidLayoutSubviews()
        try check(reader.usesSpreads && model.currentPage == 3, "narrow Mac viewport keeps double layout and logical page")
        let obsolete = reader.auditCurrentController
        model.widePages = [3]
        reader.widePagesChanged()
        try check(model.visiblePages == [3] && model.currentPage == 3, "late wide discovery keeps the focused page alone")
        try check(!reader.canDisplay(obsolete), "obsolete paired controller cannot display a known wide image")

        model.widePages = []
        reader.reloadForSettings()
        reader.go(toPage: 2, animated: false, userInitiated: true)
        let oldUnits = reader.units
        let firstTransition = reader.auditBeginTransition()
        model.widePages = [2, 3]
        reader.widePagesChanged()
        try check(reader.units == oldUnits, "wide discovery leaves unit indices stable during a transition")
        reader.pageZoomStateChanged(reader.auditCurrentController, zoomed: false)
        try check(!reader.auditCanScroll, "zoom callback cannot reenable paging during a transition")
        reader.auditFinishTransition(firstTransition, page: 2)
        await settle()
        try check(reader.units == [[0, 1], [2], [3], [4, 5]] && model.visiblePages == [2], "transition completion uses current wide-page classification")

        let stale = reader.auditBeginTransition()
        let current = reader.auditBeginTransition()
        reader.auditFinishTransition(stale, page: 0)
        await settle()
        try check(reader.auditIsTransitioning && model.currentPage == 2, "stale completion cannot replace a newer transition")
        reader.go(toPage: 4, animated: false, userInitiated: true)
        reader.auditFinishTransition(current, page: 2)
        await settle()
        try check(model.currentPage == 4, "jump queued during a transition wins over the old target")

        reader.go(toPage: 3, animated: false, userInitiated: true)
        reader.pageViewController(reader.auditPageController, willTransitionTo: [])
        reader.pageViewController(reader.auditPageController, didFinishAnimating: true, previousViewControllers: [], transitionCompleted: false)
        await settle()
        try check(model.currentPage == 3 && model.visiblePages == [3], "cancelled swipe preserves the logical wide page")

        let paths = LibraryPaths(root: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("library"),
                                 cachesRoot: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("cache"),
                                 tempRoot: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("temp"))
        let fixture = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("cbz_basic.cbz")
        guard case .imported(let book) = try BookImporter(paths: paths).importBook(from: fixture, existing: []) else {
            throw CheckFailure(label: "fixture import failed")
        }
        let source = try BookPageSource(bookID: book.id, paths: paths, format: book.format)
        defer { source.close() }
        let loader = PageImageLoader(source: source, targetPixelSize: CGSize(width: 400, height: 400))
        let wide = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).image { _ in UIColor.blue.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 200, height: 100)) }
        var continuation: CheckedContinuation<UIImage, Never>?
        let shared = Task<UIImage, Error> { await withCheckedContinuation { continuation = $0 } }
        loader.auditSeedSharedTask(shared, page: 0)
        var notifications = 0
        loader.onDecoded = { _, size in if size.width > size.height { notifications += 1 } }
        let a = Task { @MainActor in _ = try await loader.image(for: 0); return notifications }
        let b = Task { @MainActor in _ = try await loader.image(for: 0); return notifications }
        await settle()
        continuation!.resume(returning: wide)
        let results = try await [a.value, b.value]
        try check(results.allSatisfy { $0 > 0 } && notifications == 2, "every shared decode consumer receives dimensions before its image")
        _ = try await loader.image(for: 0)
        try check(notifications == 3, "cached-image consumer also receives dimensions before return")
        model.loader = loader
        loader.auditSeedCache(wide, page: 2); loader.auditSeedCache(wide, page: 3)
        obsolete.load()
        try check(obsolete.pagesOnScreen.isEmpty, "obsolete controller refuses cached wide-pair rendering")
        let portrait = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 180)).image { _ in UIColor.red.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 180)) }
        let zoom = SpreadZoomView(frame: .zero)
        reader.view.addSubview(zoom)
        for (label, images) in [("wide", [wide]), ("two portraits", [portrait, portrait])] {
            zoom.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
            zoom.configure(images: images, fitMode: .fitPage)
            for size in [CGSize(width: 1200, height: 800), CGSize(width: 1200, height: 696), CGSize(width: 1200, height: 800), CGSize(width: 600, height: 900)] {
                zoom.frame.size = size
                zoom.setNeedsLayout(); zoom.layoutIfNeeded()
                let viewport = zoom.convert(zoom.bounds, to: nil)
                let frames = zoom.drawnImages.map(\.frame)
                FileHandle.standardOutput.write(Data("GEOMETRY \(label) size=\(size) viewport=\(viewport) frames=\(frames) bounds=\(zoom.bounds) content=\(zoom.contentSize) inset=\(zoom.contentInset) offset=\(zoom.contentOffset) scale=\(zoom.zoomScale)\n".utf8))
                try check(frames.allSatisfy { viewport.insetBy(dx: -1, dy: -1).contains($0) }, "fitPage \(label) stays fully visible at \(size)")
                let combined = frames.reduce(CGRect.null) { $0.union($1) }
                try check(abs(combined.midX - viewport.midX) < 1 && abs(combined.midY - viewport.midY) < 1, "fitPage \(label) remains centered at \(size)")
            }
        }
        try await runIntentChecks(scene: scene)
        try await runVerticalGeometryChecks(source: source)
        FileHandle.standardOutput.write(Data("All \(checkCount) UIKit controller/loader/geometry/intent checks passed.\n".utf8))
    }
}

final class AuditScene: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene, let app = UIApplication.shared.delegate as? AuditApp else { return }
        Task { @MainActor in
            do { try await app.run(scene: scene); exit(0) }
            catch { FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8)); exit(1) }
        }
    }
}
