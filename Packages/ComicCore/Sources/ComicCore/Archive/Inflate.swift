import Foundation
import CZlib

enum Inflate {
    /// Inflates raw DEFLATE data. Output larger than `maxOutput` aborts (zip-bomb guard).
    static func rawInflate(_ input: Data, expectedSize: UInt64, maxOutput: UInt64, entryName: String) throws -> Data {
        var stream = z_stream()
        var status = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw ComicError.ioError(detail: "zlib init \(status)") }
        defer { inflateEnd(&stream) }

        let initial = Int(min(max(expectedSize, 1024), maxOutput))
        var output = Data(count: initial)
        var produced = 0
        let chunk = 256 * 1024

        try input.withUnsafeBytes { (inBuf: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer(mutating: inBuf.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(inBuf.count)
            repeat {
                if produced == output.count {
                    let grown = UInt64(output.count) + UInt64(chunk)
                    guard grown <= maxOutput + UInt64(chunk) else {
                        throw ComicError.entryTooLarge(entry: entryName, size: grown, limit: maxOutput)
                    }
                    output.count += chunk
                }
                let space = output.count - produced
                status = output.withUnsafeMutableBytes { (outBuf: UnsafeMutableRawBufferPointer) -> Int32 in
                    stream.next_out = outBuf.bindMemory(to: Bytef.self).baseAddress! + produced
                    stream.avail_out = uInt(space)
                    let s = inflate(&stream, Z_NO_FLUSH)
                    produced += space - Int(stream.avail_out)
                    return s
                }
                if UInt64(produced) > maxOutput {
                    throw ComicError.entryTooLarge(entry: entryName, size: UInt64(produced), limit: maxOutput)
                }
                if status == Z_STREAM_END { break }
                if status == Z_BUF_ERROR && stream.avail_in == 0 {
                    throw ComicError.truncatedArchive
                }
                guard status == Z_OK || status == Z_BUF_ERROR else {
                    throw ComicError.corruptArchive(detail: "deflate data error in \(entryName)")
                }
            } while true
        }
        output.count = produced
        return output
    }
}
