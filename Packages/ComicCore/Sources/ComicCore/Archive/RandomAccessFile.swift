import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Thread-safe positional reads (pread) on a file descriptor.
public final class RandomAccessFile: @unchecked Sendable {
    public let size: UInt64
    private let fd: Int32

    public init(url: URL) throws {
        let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY)
        }
        guard fd >= 0 else {
            throw ComicError.sourceUnreadable(detail: String(cString: strerror(errno)))
        }
        var st = stat()
        guard fstat(fd, &st) == 0 else {
            close(fd)
            throw ComicError.ioError(detail: String(cString: strerror(errno)))
        }
        self.fd = fd
        self.size = UInt64(st.st_size)
    }

    deinit { close(fd) }

    /// Reads exactly `count` bytes at `offset` or throws `.truncatedArchive`.
    public func read(at offset: UInt64, count: Int) throws -> Data {
        if count == 0 { return Data() }
        guard offset <= size, UInt64(count) <= size - offset else { throw ComicError.truncatedArchive }
        var data = Data(count: count)
        var done = 0
        try data.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) in
            while done < count {
                let r = pread(fd, buf.baseAddress! + done, count - done, off_t(offset) + off_t(done))
                if r < 0 {
                    if errno == EINTR { continue }
                    throw ComicError.ioError(detail: String(cString: strerror(errno)))
                }
                if r == 0 { throw ComicError.truncatedArchive }
                done += r
            }
        }
        return data
    }
}

extension Data {
    @inline(__always) func u16(_ o: Int) -> UInt16 {
        UInt16(self[startIndex + o]) | UInt16(self[startIndex + o + 1]) << 8
    }
    @inline(__always) func u32(_ o: Int) -> UInt32 {
        UInt32(u16(o)) | UInt32(u16(o + 2)) << 16
    }
    @inline(__always) func u64(_ o: Int) -> UInt64 {
        UInt64(u32(o)) | UInt64(u32(o + 4)) << 32
    }
}
