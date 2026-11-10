import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import ComicCore

/// Turns pages into named files for the share sheet.
///
/// Files keep the archive's own bytes, so nothing is lost and the page leaves at its full
/// resolution. Only formats that other apps cannot be relied on to open are converted.
enum SharedPageFiles {
    private static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SharedPages", isDirectory: true)
    }

    static func write(pages: [Int], source: BookPageSource, bookName: String) async throws -> [URL] {
        removeAll()
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var files: [URL] = []
        for page in pages {
            let original = try await source.pageData(page)
            try Task.checkCancellation()
            let (data, fileExtension) = try shareable(original)
            let file = dir.appendingPathComponent(PageFileName.make(book: bookName, page: page,
                                                                    pageCount: source.pageCount,
                                                                    fileExtension: fileExtension))
            try data.write(to: file)
            files.append(file)
        }
        return files
    }

    /// The contents decide, not the archive's file name: a ".jpg" entry can hold anything.
    static func shareable(_ data: Data) throws -> (data: Data, fileExtension: String) {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier) else { throw ImageDecodeError.undecodable }
        switch type {
        case .jpeg: return (data, "jpg")
        case .png: return (data, "png")
        case .heic: return (data, "heic")
        case .gif: return (data, "gif")
        default:
            let side = CGFloat(ImageDecoder.maxDecodedSide)
            let image = try ImageDecoder.decode(data, targetWidth: side, targetHeight: side)
            guard let png = ImageDecoder.pngData(image) else { throw ImageDecodeError.undecodable }
            return (png, "png")
        }
    }

    /// Not tied to the sheet closing: AirDrop can still be reading a file by then.
    static func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// Shows the share sheet for `files`, anchored on the view this backs (iPad needs an anchor).
struct ShareSheetPresenter: UIViewRepresentable {
    let files: [URL]?
    let onDismiss: () -> Void

    final class Coordinator {
        var presented: [URL]?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        guard let files else {
            coordinator.presented = nil
            return
        }
        guard coordinator.presented != files else { return }
        coordinator.presented = files
        // Presenting is not allowed while SwiftUI is still updating its views.
        DispatchQueue.main.async {
            guard let host = Self.viewController(of: view) else {
                onDismiss()
                return
            }
            let sheet = UIActivityViewController(activityItems: files, applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = view
            sheet.popoverPresentationController?.sourceRect = view.bounds
            sheet.completionWithItemsHandler = { _, _, _, _ in onDismiss() }
            host.present(sheet, animated: true)
        }
    }

    private static func viewController(of view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let next = responder?.next {
            if let controller = next as? UIViewController { return controller }
            responder = next
        }
        return nil
    }
}
