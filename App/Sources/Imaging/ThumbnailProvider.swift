import UIKit
import ComicCore

/// Page thumbnails for the grid: memory cache → disk cache → decode.
/// Work runs on a small background queue; requests can be cancelled.
final class ThumbnailProvider: @unchecked Sendable {
    static let maxPixel = 320

    private let source: BookPageSource
    private let dir: URL
    private let memory = NSCache<NSNumber, UIImage>()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 2
        q.qualityOfService = .utility
        return q
    }()

    init(source: BookPageSource, cacheDir: URL) {
        self.source = source
        self.dir = cacheDir
        memory.countLimit = 300
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func cached(_ page: Int) -> UIImage? { memory.object(forKey: NSNumber(value: page)) }

    /// Returns nil if the page cannot be produced yet (solid archive still preparing) or failed.
    func thumbnail(_ page: Int) async -> UIImage? {
        if let m = cached(page) { return m }
        let op = BlockOperation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
                op.addExecutionBlock { [weak op, self] in
                    if op?.isCancelled == true { cont.resume(returning: nil); return }
                    cont.resume(returning: self.produce(page))
                }
                queue.addOperation(op)
            }
        } onCancel: {
            op.cancel()
        }
    }

    private func produce(_ page: Int) -> UIImage? {
        let file = dir.appendingPathComponent("\(page).jpg")
        if let data = try? Data(contentsOf: file), let img = UIImage(data: data) {
            memory.setObject(img, forKey: NSNumber(value: page))
            return img
        }
        guard source.isPageReady(page), let data = try? source.pageDataSync(page),
              let img = try? ImageDecoder.decodeThumbnail(data, maxPixel: Self.maxPixel) else { return nil }
        memory.setObject(img, forKey: NSNumber(value: page))
        if let jpeg = ImageDecoder.jpegData(img, quality: 0.7) { try? jpeg.write(to: file, options: .atomic) }
        return img
    }

    func cancelAll() { queue.cancelAllOperations() }
}

/// Library cover images (small, read from Books/<id>/cover.jpg).
final class CoverCache: @unchecked Sendable {
    static let shared = CoverCache()
    private let memory = NSCache<NSString, UIImage>()

    func image(for url: URL) async -> UIImage? {
        if let m = memory.object(forKey: url.path as NSString) { return m }
        let img: UIImage? = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? ImageDecoder.decodeThumbnail(data, maxPixel: 600)
        }.value
        if let img { memory.setObject(img, forKey: url.path as NSString) }
        return img
    }

    func invalidate(_ url: URL) { memory.removeObject(forKey: url.path as NSString) }
    func purge() { memory.removeAllObjects() }
}
