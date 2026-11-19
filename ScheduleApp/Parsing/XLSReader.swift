import Foundation

/// Читатель строк SST, которые могут быть разорваны записями CONTINUE.
final class SegReader {
    let segs: [[UInt8]]
    var si: Int = 0
    var pi: Int = 0

    init(_ s: [[UInt8]]) {
        segs = s
    }

    func normalize() {
        while si < segs.count && pi >= segs[si].count {
            si += 1
            pi = 0
        }
    }

    func u8() -> Int? {
        normalize()
        guard si < segs.count else { return nil }
        let v = Int(segs[si][pi])
        pi += 1
        return v
    }

    func u16() -> Int? {
        guard let a = u8(), let b = u8() else { return nil }
        return a | (b << 8)
    }

    func u32() -> Int? {
        guard let a = u16(), let b = u16() else { return nil }
        return a | (b << 16)
    }

    func skip(_ n: Int) {
        var left = n
        while left > 0 {
            normalize()
            guard si < segs.count else { return }
            let avail = segs[si].count - pi
            let k = min(avail, left)
            pi += k
            left -= k
        }
    }

    func chars(_ count: Int, wide w: Bool) -> String? {
        var wide = w
        var units: [UInt16] = []
        units.reserveCapacity(count)
        var remaining = count
        while remaining > 0 {
            if si >= segs.count { return nil }
            if pi >= segs[si].count {
                si += 1
                pi = 0
                if si >= segs.count { return nil }
                if segs[si].isEmpty { continue }
                // Продолжение строки в новом сегменте начинается с байта флагов
                wide = (segs[si][0] & 1) != 0
                pi = 1
                continue
            }
            let seg = segs[si]
            if wide {
                if pi + 1 >= seg.count {
                    pi = seg.count
                    continue
                }
                units.append(UInt16(seg[pi]) | (UInt16(seg[pi + 1]) << 8))
                pi += 2
            } else {
                units.append(UInt16(seg[pi]))
                pi += 1
            }
            remaining -= 1
        }
        return String(decoding: units, as: UTF16.self)
    }
}

enum XLSReader {
    static func read(_ data: Data) throws -> [RawSheet] {
        let cfb = try CFB(data: data)
        guard let wb = cfb.stream(named: ["Workbook", "Book"]) else { throw ExcelError.noWorkbook }
        return parse(wb)
    }

    private struct SheetInfo {
        var name: String
        var offset: Int
        var type: Int
    }

    static func decodeString(_ b: [UInt8], from: Int, count: Int, wide: Bool) -> String {
        var units: [UInt16] = []
        var p = from
        for _ in 0..<max(count, 0) {
            if wide {
                if p + 1 >= b.count { break }
                units.append(UInt16(b[p]) | (UInt16(b[p + 1]) << 8))
                p += 2
            } else {
                if p >= b.count { break }
                units.append(UInt16(b[p]))
                p += 1
            }
        }
        return String(decoding: units, as: UTF16.self)
    }

    static func parseSST(_ segs: [[UInt8]]) -> [String] {
        let r = SegReader(segs)
        _ = r.u32()
        guard let unique = r.u32() else { return [] }
        var out: [String] = []
        out.reserveCapacity(min(unique, 1_000_000))
        var i = 0
        while i < unique {
            i += 1
            guard let cch = r.u16(), let flags = r.u8() else { break }
            var runs = 0
            var ext = 0
            if flags & 0x08 != 0 { runs = r.u16() ?? 0 }
            if flags & 0x04 != 0 { ext = r.u32() ?? 0 }
            guard let s = r.chars(cch, wide: (flags & 0x01) != 0) else { break }
            if runs > 0 { r.skip(runs * 4) }
            if ext > 0 { r.skip(ext) }
            out.append(s)
        }
        return out
    }

    static func decodeRK(_ rk: Int) -> Double {
        let u = UInt32(truncatingIfNeeded: rk)
        var v: Double
        if u & 0x02 != 0 {
            v = Double(Int32(bitPattern: u) >> 2)
        } else {
            let bits = UInt64(u & 0xFFFFFFFC) << 32
            v = Double(bitPattern: bits)
        }
        if u & 0x01 != 0 { v /= 100 }
        return v
    }

    private static func parse(_ wb: [UInt8]) -> [RawSheet] {
        var sst: [String] = []
        var infos: [SheetInfo] = []
        var pos = 0
        var depth = 0

        // Глобальный поток книги: листы и общие строки
        while pos + 4 <= wb.count {
            let id = rdU16(wb, pos)
            let len = rdU16(wb, pos + 2)
            let body = pos + 4
            if body + len > wb.count { break }
            var next = body + len
            switch id {
            case 0x0809:
                depth += 1
            case 0x000A:
                depth -= 1
            case 0x0085:
                let off = rdU32(wb, body)
                let type = len > 5 ? Int(wb[body + 5]) : 0
                let cch = len > 6 ? Int(wb[body + 6]) : 0
                let flags = len > 7 ? Int(wb[body + 7]) : 0
                let name = decodeString(wb, from: body + 8, count: cch, wide: (flags & 1) != 0)
                infos.append(SheetInfo(name: name, offset: off, type: type))
            case 0x00FC:
                var segs: [[UInt8]] = [Array(wb[body..<(body + len)])]
                var p2 = body + len
                while p2 + 4 <= wb.count && rdU16(wb, p2) == 0x003C {
                    let l2 = rdU16(wb, p2 + 2)
                    if p2 + 4 + l2 > wb.count { break }
                    segs.append(Array(wb[(p2 + 4)..<(p2 + 4 + l2)]))
                    p2 += 4 + l2
                }
                sst = parseSST(segs)
                next = p2
            default:
                break
            }
            pos = next
            if depth <= 0 && id == 0x000A { break }
        }

        var sheets: [RawSheet] = []
        for info in infos where info.type == 0 {
            sheets.append(parseSheet(wb, offset: info.offset, name: info.name, sst: sst))
        }
        return sheets
    }

    private static func parseSheet(_ wb: [UInt8], offset: Int, name: String, sst: [String]) -> RawSheet {
        var cells: [Int: [Int: String]] = [:]
        var merges: [MergeRange] = []
        var pos = offset
        var depth = 0
        var pendingFormula: (Int, Int)? = nil

        func put(_ r: Int, _ c: Int, _ v: String) {
            if v.isEmpty { return }
            cells[r, default: [:]][c] = v
        }

        while pos + 4 <= wb.count {
            let id = rdU16(wb, pos)
            let len = rdU16(wb, pos + 2)
            let body = pos + 4
            if body + len > wb.count { break }
            pos = body + len

            if id == 0x0809 { depth += 1; continue }
            if id == 0x000A {
                depth -= 1
                if depth <= 0 { break }
                continue
            }
            if depth != 1 { continue }

            switch id {
            case 0x00FD: // LABELSST
                if len >= 10 {
                    let r = rdU16(wb, body)
                    let c = rdU16(wb, body + 2)
                    let idx = rdU32(wb, body + 6)
                    if idx >= 0 && idx < sst.count { put(r, c, sst[idx]) }
                }
            case 0x0203: // NUMBER
                if len >= 14 {
                    put(rdU16(wb, body), rdU16(wb, body + 2), numString(rdDouble(wb, body + 6)))
                }
            case 0x027E: // RK
                if len >= 10 {
                    put(rdU16(wb, body), rdU16(wb, body + 2), numString(decodeRK(rdU32(wb, body + 6))))
                }
            case 0x00BD: // MULRK
                if len >= 12 {
                    let r = rdU16(wb, body)
                    let first = rdU16(wb, body + 2)
                    let count = (len - 6) / 6
                    var i = 0
                    while i < count {
                        let off = body + 4 + i * 6
                        put(r, first + i, numString(decodeRK(rdU32(wb, off + 2))))
                        i += 1
                    }
                }
            case 0x0204: // LABEL
                if len >= 9 {
                    let r = rdU16(wb, body)
                    let c = rdU16(wb, body + 2)
                    let cch = rdU16(wb, body + 6)
                    let flags = Int(wb[body + 8])
                    put(r, c, decodeString(wb, from: body + 9, count: cch, wide: (flags & 1) != 0))
                }
            case 0x0006: // FORMULA
                if len >= 14 {
                    let r = rdU16(wb, body)
                    let c = rdU16(wb, body + 2)
                    let isSpecial = wb[body + 12] == 0xFF && wb[body + 13] == 0xFF
                    if isSpecial {
                        if wb[body + 6] == 0 { pendingFormula = (r, c) }
                    } else {
                        put(r, c, numString(rdDouble(wb, body + 6)))
                    }
                }
            case 0x0207: // STRING (результат формулы)
                if let (r, c) = pendingFormula, len >= 3 {
                    let cch = rdU16(wb, body)
                    let flags = Int(wb[body + 2])
                    put(r, c, decodeString(wb, from: body + 3, count: cch, wide: (flags & 1) != 0))
                    pendingFormula = nil
                }
            case 0x00E5: // MERGEDCELLS
                if len >= 2 {
                    let n = rdU16(wb, body)
                    var i = 0
                    while i < n && body + 2 + (i + 1) * 8 <= body + len {
                        let o = body + 2 + i * 8
                        merges.append(MergeRange(r0: rdU16(wb, o), r1: rdU16(wb, o + 2),
                                                 c0: rdU16(wb, o + 4), c1: rdU16(wb, o + 6)))
                        i += 1
                    }
                }
            default:
                break
            }
        }
        return RawSheet(name: name, cells: cells, merges: merges)
    }
}
