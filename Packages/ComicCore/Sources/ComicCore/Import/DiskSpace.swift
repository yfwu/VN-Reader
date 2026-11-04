import Foundation

public protocol DiskSpaceProviding: Sendable {
    /// Bytes available for important (user-initiated) data at `url`'s volume.
    func availableCapacity(for url: URL) -> Int64?
}

public struct SystemDiskSpace: DiskSpaceProviding {
    public init() {}

    public func availableCapacity(for url: URL) -> Int64? {
        #if os(iOS) || os(macOS) || os(visionOS)
        if let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let c = v.volumeAvailableCapacityForImportantUsage, c > 0 {
            return c
        }
        #endif
        let path = FileManager.default.fileExists(atPath: url.path) ? url.path : url.deletingLastPathComponent().path
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
           let free = attrs[.systemFreeSize] as? NSNumber {
            return free.int64Value
        }
        return nil
    }
}

public enum DiskSpacePolicy {
    /// Space kept free for the system and other apps.
    public static let reserve: Int64 = 200 * 1024 * 1024

    public static func check(required: Int64, at url: URL, provider: DiskSpaceProviding) throws {
        guard let available = provider.availableCapacity(for: url) else { return }
        if required + reserve > available {
            throw ComicError.insufficientDiskSpace(required: required + reserve, available: available)
        }
    }
}
