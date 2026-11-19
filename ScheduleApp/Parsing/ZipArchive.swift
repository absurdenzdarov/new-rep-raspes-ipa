import Foundation
import Compression

/// Минимальный читатель ZIP (для .xlsx): stored + deflate.
final class ZipArchive {
    struct Entry {
        var method: Int
        var compSize: Int
        var size: Int
        var offset: Int
    }

    private let bytes: [UInt8]
    private var entries: [String: Entry] = [:]

    var names: [String] { return Array(entries.keys) }

    init?(data: Data) {
        bytes = [UInt8](data)
        guard bytes.count >= 22 else { return nil }
        // Ищем End Of Central Directory
        var eocd = -1
        var i = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 65535)
        while i >= lowest {
            if bytes[i] == 0x50 && bytes[i + 1] == 0x4B && bytes[i + 2] == 0x05 && bytes[i + 3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { return nil }
        let total = rdU16(bytes, eocd + 10)
        var p = rdU32(bytes, eocd + 16)
        var n = 0
        while n < total && p + 46 <= bytes.count {
            if rdU32(bytes, p) != 0x02014B50 { break }
            let method = rdU16(bytes, p + 10)
            let compSize = rdU32(bytes, p + 20)
            let size = rdU32(bytes, p + 24)
            let nameLen = rdU16(bytes, p + 28)
            let extraLen = rdU16(bytes, p + 30)
            let commentLen = rdU16(bytes, p + 32)
            let localOffset = rdU32(bytes, p + 42)
            if p + 46 + nameLen > bytes.count { break }
            let nameBytes = Array(bytes[(p + 46)..<(p + 46 + nameLen)])
            let name = String(decoding: nameBytes, as: UTF8.self)
            entries[name] = Entry(method: method, compSize: compSize, size: size, offset: localOffset)
            p += 46 + nameLen + extraLen + commentLen
            n += 1
        }
        if entries.isEmpty { return nil }
    }

    func read(_ name: String) -> Data? {
        guard let e = entries[name] else { return nil }
        let h = e.offset
        guard h + 30 <= bytes.count, rdU32(bytes, h) == 0x04034B50 else { return nil }
        let nameLen = rdU16(bytes, h + 26)
        let extraLen = rdU16(bytes, h + 28)
        let start = h + 30 + nameLen + extraLen
        let end = start + e.compSize
        guard start >= 0, end <= bytes.count else { return nil }
        if e.method == 0 {
            return Data(bytes[start..<end])
        }
        if e.method == 8 {
            return inflate(Array(bytes[start..<end]), expected: e.size)
        }
        return nil
    }

    private func inflate(_ src: [UInt8], expected: Int) -> Data? {
        if expected == 0 { return Data() }
        if src.isEmpty { return nil }
        var dst = [UInt8](repeating: 0, count: expected)
        let written: Int = src.withUnsafeBufferPointer { (sp: UnsafeBufferPointer<UInt8>) -> Int in
            return dst.withUnsafeMutableBufferPointer { (dp: inout UnsafeMutableBufferPointer<UInt8>) -> Int in
                return compression_decode_buffer(dp.baseAddress!, expected, sp.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        if written == 0 { return nil }
        return Data(dst[0..<written])
    }
}
