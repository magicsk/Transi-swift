//
//  Gzip.swift
//  Transi
//
//  Created by magic_sk on 26/02/2026.
//

import Foundation
import zlib

func decompressGzipToFile(from compressedData: Data, to destinationURL: URL) -> Bool {
    FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
    guard let fileHandle = try? FileHandle(forWritingTo: destinationURL) else { return false }
    defer { fileHandle.closeFile() }

    var stream = z_stream()
    stream.avail_in = uInt(compressedData.count)

    let result = compressedData.withUnsafeBytes { rawBuffer -> Bool in
        guard let baseAddress = rawBuffer.baseAddress else { return false }
        stream.next_in = UnsafeMutablePointer(mutating: baseAddress.assumingMemoryBound(to: UInt8.self))

        // windowBits 15 + 16 = gzip auto-detect
        guard inflateInit2_(&stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return false
        }

        let chunkSize = 65536
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }
        var status: Int32

        repeat {
            stream.avail_out = uInt(chunkSize)
            stream.next_out = buffer

            status = inflate(&stream, Z_NO_FLUSH)
            guard status == Z_OK || status == Z_STREAM_END else {
                inflateEnd(&stream)
                return false
            }

            let written = chunkSize - Int(stream.avail_out)
            if written > 0 {
                fileHandle.write(Data(bytesNoCopy: buffer, count: written, deallocator: .none))
            }
        } while status != Z_STREAM_END

        inflateEnd(&stream)
        return true
    }

    return result
}
