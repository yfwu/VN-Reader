import UIKit
import ImageIO
import UniformTypeIdentifiers
import ComicCore

enum ImageDecodeError: Error, Equatable {
    case undecodable
    case tooLarge(width: Int, height: Int)
}

/// Downsampling decoder built on ImageIO (JPEG, PNG, WebP, GIF, HEIC, AVIF…).
///
/// Never decodes a full-resolution bitmap unless it is needed: the image is
/// decoded straight to the requested pixel size on the calling (background) thread.
enum ImageDecoder {
    /// Images above this many source pixels are refused (memory safety). JPEG can be
    /// decoded straight to a reduced size; PNG / WebP / others are fully decoded by
    /// ImageIO before downscaling, so their limit is lower (~256 MB transient).
    static let maxSourcePixelsJPEG = 200_000_000
    static let maxSourcePixelsOther = 64_000_000
    /// Upper bound for a decoded page bitmap (~96 MB at 4 bytes/pixel).
    static let maxDecodedPixels = 24_000_000
    /// Longest decoded side; larger layers exceed the GPU texture limit.
    static let maxDecodedSide = 16_384

    static func sourceLimit(_ src: CGImageSource) -> Int {
        let type = CGImageSourceGetType(src) as String?
        return type == UTType.jpeg.identifier ? maxSourcePixelsJPEG : maxSourcePixelsOther
    }

    struct Info { let width: Int; let height: Int }

    static func info(_ source: CGImageSource) -> Info? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let o = (props[kCGImagePropertyOrientation] as? UInt32) ?? 1
        return o >= 5 ? Info(width: h, height: w) : Info(width: w, height: h)
    }

    /// Decodes for display. `targetWidth` is the widest the page will be shown
    /// at zoom 1 (in pixels); tall strips keep enough width to stay sharp.
    static func decode(_ data: Data, targetWidth: CGFloat, targetHeight: CGFloat) throws -> UIImage {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, opts),
              CGImageSourceGetCount(src) > 0, let info = info(src),
              info.width > 0, info.height > 0 else { throw ImageDecodeError.undecodable }
        if info.width * info.height > sourceLimit(src) {
            throw ImageDecodeError.tooLarge(width: info.width, height: info.height)
        }
        let w = CGFloat(info.width), h = CGFloat(info.height)
        // Scale so the page is at least as sharp as fitting either dimension.
        var scale = min(1, max(targetWidth / w, targetHeight / h))
        let decodedPixels = w * h * scale * scale
        if decodedPixels > CGFloat(maxDecodedPixels) { scale *= sqrt(CGFloat(maxDecodedPixels) / decodedPixels) }
        let maxPixel = min(maxDecodedSide, max(1, Int((max(w, h) * scale).rounded(.up))))
        return try thumbnail(src, maxPixel: maxPixel)
    }

    static func decodeThumbnail(_ data: Data, maxPixel: Int) throws -> UIImage {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(src) > 0, let info = info(src) else { throw ImageDecodeError.undecodable }
        if info.width * info.height > sourceLimit(src) {
            throw ImageDecodeError.tooLarge(width: info.width, height: info.height)
        }
        return try thumbnail(src, maxPixel: maxPixel)
    }

    private static func thumbnail(_ src: CGImageSource, maxPixel: Int) throws -> UIImage {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw ImageDecodeError.undecodable
        }
        return UIImage(cgImage: cg)
    }

    static func jpegData(_ image: UIImage, quality: CGFloat = 0.8) -> Data? {
        encoded(image, as: .jpeg, options: [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    }

    static func pngData(_ image: UIImage) -> Data? {
        encoded(image, as: .png, options: nil)
    }

    private static func encoded(_ image: UIImage, as type: UTType, options: CFDictionary?) -> Data? {
        guard let cg = image.cgImage else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, options)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

/// Cover thumbnails for the library grid (created at import).
struct ImageIOCoverRenderer: CoverRendering {
    func coverJPEG(from imageData: Data) -> Data? {
        guard let img = try? ImageDecoder.decodeThumbnail(imageData, maxPixel: 600) else { return nil }
        return ImageDecoder.jpegData(img, quality: 0.8)
    }
}
