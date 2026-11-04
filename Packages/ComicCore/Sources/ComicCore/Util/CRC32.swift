import Foundation
import CZlib

/// Incremental CRC-32 (zlib implementation).
public struct CRC32: Sendable {
    public private(set) var value: UInt32 = 0
    public init() {}

    public mutating func update(_ data: Data) {
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            guard let base = buf.bindMemory(to: Bytef.self).baseAddress else { return }
            var remaining = buf.count
            var p = base
            var crc = uLong(value)
            while remaining > 0 {
                let n = min(remaining, Int(UInt32.max / 2))
                crc = crc32(crc, p, uInt(n))
                p += n
                remaining -= n
            }
            value = UInt32(truncatingIfNeeded: crc)
        }
    }

    public static func checksum(_ data: Data) -> UInt32 {
        var c = CRC32()
        c.update(data)
        return c.value
    }
}
