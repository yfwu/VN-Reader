import UIKit
import ComicCore

/// Decoded page bitmaps for one open book: on-demand loading, bounded memory
/// cache, a small prefetch window and cancellation of stale work.
@MainActor
final class PageImageLoader {
    enum Failure: Error { case decode(ErrorExplanation) }

    let source: BookPageSource
    /// Reports decoded pixel sizes (used to detect wide double-page images).
    var onDecoded: ((Int, CGSize) -> Void)?
    private let cache = NSCache<NSNumber, UIImage>()
    private var inFlight: [Int: Task<UIImage, Error>] = [:]
    private var target: CGSize
    private var memoryObserver: NSObjectProtocol?

    init(source: BookPageSource, targetPixelSize: CGSize) {
        self.source = source
        self.target = targetPixelSize
        let physical = ProcessInfo.processInfo.physicalMemory
        // ~1/10 of RAM, between 120 MB and 400 MB (iPad mini 6 has 4 GB → ~400 MB).
        cache.totalCostLimit = Int(min(max(physical / 10, 120 << 20), 400 << 20))
        cache.countLimit = 12
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.purge() }
        }
    }

    deinit {
        if let o = memoryObserver { NotificationCenter.default.removeObserver(o) }
        for t in inFlight.values { t.cancel() }
    }

    /// Called on rotation / window resize. Cached images stay valid (they were
    /// decoded for the larger of both orientations).
    func updateTarget(_ size: CGSize) {
        if size.width > target.width || size.height > target.height {
            target = CGSize(width: max(size.width, target.width), height: max(size.height, target.height))
        }
    }

    func purge() {
        cache.removeAllObjects()
    }

    func cachedImage(_ page: Int) -> UIImage? { cache.object(forKey: NSNumber(value: page)) }

    func image(for page: Int) async throws -> UIImage {
        if let img = cachedImage(page) { return img }
        if let t = inFlight[page] { return try await awaitShared(t, page: page) }
        let source = self.source
        let target = self.target
        let path = source.manifest.pages.indices.contains(page) ? source.manifest.pages[page].path : "?"
        let task = Task.detached(priority: .userInitiated) { () throws -> UIImage in
            let data = try await source.pageData(page)
            try Task.checkCancellation()
            do {
                return try ImageDecoder.decode(data, targetWidth: target.width, targetHeight: target.height)
            } catch ImageDecodeError.tooLarge(let w, let h) {
                throw Failure.decode(ErrorMessages.imageTooLarge(w, h))
            } catch {
                throw Failure.decode(ErrorMessages.imageDecodeFailed(path))
            }
        }
        inFlight[page] = task
        defer { if inFlight[page] == task { inFlight[page] = nil } }
        let img = try await awaitShared(task, page: page)
        let cost = Int(img.size.width * img.size.height * img.scale * img.scale * 4)
        cache.setObject(img, forKey: NSNumber(value: page), cost: cost)
        onDecoded?(page, img.size)
        return img
    }

    /// Awaits a shared decode task. If the prefetch window cancelled it while this
    /// caller still needs the page (caller not cancelled), the load is restarted.
    private func awaitShared(_ t: Task<UIImage, Error>, page: Int) async throws -> UIImage {
        do {
            return try await t.value
        } catch is CancellationError where !Task.isCancelled {
            if inFlight[page] == t { inFlight[page] = nil }
            return try await image(for: page)
        }
    }

    /// Keeps only work for pages in `keep` running; starts loads for missing ones.
    func prefetch(_ pages: [Int]) {
        let keep = Set(pages)
        for (p, t) in inFlight where !keep.contains(p) {
            t.cancel()
            inFlight[p] = nil
        }
        for p in pages where cachedImage(p) == nil && inFlight[p] == nil && source.manifest.pages.indices.contains(p) {
            Task { _ = try? await self.image(for: p) }
        }
    }

    func cancelAll() {
        for t in inFlight.values { t.cancel() }
        inFlight.removeAll()
    }
}
