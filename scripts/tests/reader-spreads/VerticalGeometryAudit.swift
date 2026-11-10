import UIKit
import ComicCore

extension AuditApp {
    @MainActor func runVerticalGeometryChecks(source: BookPageSource) async throws {
        let tall = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 500)).image { _ in
            UIColor.green.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 500))
        }
        func mount(_ model: ReaderViewModel, size: CGSize) -> VerticalReaderController {
            let reader = VerticalReaderController(model: model)
            window?.rootViewController = reader
            reader.loadViewIfNeeded()
            window?.addSubview(reader.view)
            reader.view.frame = CGRect(origin: .zero, size: size)
            reader.view.setNeedsLayout(); reader.view.layoutIfNeeded()
            reader.viewWillLayoutSubviews(); reader.viewDidLayoutSubviews()
            reader.auditTable.layoutIfNeeded()
            return reader
        }
        let cachedModel = ReaderViewModel()
        cachedModel.layout = .vertical
        let loader = PageImageLoader(source: source, targetPixelSize: CGSize(width: 600, height: 600))
        for page in 0..<cachedModel.pageCount { loader.auditSeedCache(tall, page: page) }
        cachedModel.loader = loader
        let cached = mount(cachedModel, size: CGSize(width: 400, height: 600))
        let firstRow = cached.auditTable.rectForRow(at: IndexPath(row: 0, section: 0))
        FileHandle.standardOutput.write(Data("CACHED VERTICAL row=\(firstRow) drawn=\(cached.pagesOnScreen().map(\.frame))\n".utf8))
        try check(abs(firstRow.height - 2000) < 1, "cached tall page gets its full-width row height on first layout")
        try check(cached.pagesOnScreen().contains { $0.page == 0 && abs($0.frame.width - 400) < 1 && abs($0.frame.height - 2000) < 1 },
                  "cached tall image fills the row instead of becoming a narrow strip")
        cached.view.frame.size = CGSize(width: 600, height: 800)
        cached.view.setNeedsLayout(); cached.view.layoutIfNeeded()
        cached.auditTable.layoutIfNeeded()
        try check(abs(cached.auditTable.rectForRow(at: IndexPath(row: 0, section: 0)).height - 3000) < 1 &&
                  cached.pagesOnScreen().contains { $0.page == 0 && abs($0.frame.width - 600) < 1 },
                  "cached tall page keeps the correct aspect after viewport resize")
        try check(cachedModel.userPageEvents.isEmpty, "cached aspect sizing and viewport changes remain passive")

        let lateModel = ReaderViewModel()
        lateModel.layout = .vertical
        let late = mount(lateModel, size: CGSize(width: 400, height: 600))
        // Start with the pending image onscreen, then navigate beyond it before
        // its decode completes, as a real delayed cell load can do.
        late.go(toPage: 2, animated: false, userInitiated: true)
        lateModel.pageEvents = []
        let beforeOffset = late.auditTable.contentOffset.y
        let beforeRow = late.auditTable.rectForRow(at: IndexPath(row: 2, section: 0)).minY
        // The real image loader fills its cache before handing the decode result
        // to the cell. Old-height compensation must still use the prior layout.
        let lateLoader = PageImageLoader(source: source, targetPixelSize: CGSize(width: 400, height: 600))
        lateLoader.auditSeedCache(tall, page: 0)
        lateModel.loader = lateLoader
        late.auditAspect(0, size: tall.size)
        lateModel.loader = nil
        await settle()
        late.auditTable.layoutIfNeeded()
        let delta: CGFloat = (5 - 1.45) * 400
        FileHandle.standardOutput.write(Data("LATE VERTICAL offset=\(beforeOffset)→\(late.auditTable.contentOffset.y) row=\(beforeRow)→\(late.auditTable.rectForRow(at: IndexPath(row: 2, section: 0)).minY) expectedDelta=\(delta)\n".utf8))
        try check(abs(late.auditTable.contentOffset.y - beforeOffset - delta) < 1 &&
                  abs(late.auditTable.rectForRow(at: IndexPath(row: 2, section: 0)).minY - beforeRow - delta) < 1,
                  "late decode above viewport compensates the old fallback height even with a populated cache")
        try check(lateModel.currentPage == 2 && lateModel.userPageEvents.isEmpty,
                  "late decoded height adjustment preserves logical focus without progress writes")
        cachedModel.pager = nil; lateModel.pager = nil
        cachedModel.loader = nil; lateModel.loader = nil
    }
}
