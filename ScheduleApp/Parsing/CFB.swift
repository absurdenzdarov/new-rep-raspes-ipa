import Foundation

/// Чтение контейнера OLE2 / Compound File Binary (старый формат .xls).
final class CFB {
    private let data: [UInt8]
    private var sectorSize: Int = 512
    private var miniSectorSize: Int = 64
    private var miniCutoff: Int = 4096
    private var fat: [Int] = []
    private var miniFat: [Int] = []
    private var miniStream: [UInt8] = []

    struct Entry {
        var name: String
        var type: Int
        var start: Int
        var size: Int
    }
    private(set) var entries: [Entry] = []

    private static let endOfChain = 0xFFFFFFFC

    init(data: Data) throws {
        self.data = [UInt8](data)
        guard self.data.count >= 512 else { throw ExcelError.badContainer }
        let sig: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        guard Array(self.data[0..<8]) == sig else { throw ExcelError.badContainer }

        let sectorShift = rdU16(self.data, 0x1E)
        let miniShift = rdU16(self.data, 0x20)
        guard sectorShift >= 7 && sectorShift <= 16 && miniShift >= 4 && miniShift <= 12 else {
            throw ExcelError.badContainer
        }
        sectorSize = 1 << sectorShift
        miniSectorSize = 1 << miniShift
        miniCutoff = rdU32(self.data, 0x38)

        let dirStart = rdU32(self.data, 0x30)
        let miniFatStart = rdU32(self.data, 0x3C)
        let difatStart = rdU32(self.data, 0x44)
        let numDifat = rdU32(self.data, 0x48)

        // Список секторов FAT
        var fatSectors: [Int] = []
        for i in 0..<109 {
            let s = rdU32(self.data, 0x4C + i * 4)
            if s < CFB.endOfChain { fatSectors.append(s) }
        }
        var difat = difatStart
        var guardCount = 0
        while difat < CFB.endOfChain && guardCount < max(numDifat, 1) + 8 {
            guard let sec = sector(difat) else { break }
            let perSector = sectorSize / 4
            for i in 0..<(perSector - 1) {
                let s = rdU32(sec, i * 4)
                if s < CFB.endOfChain { fatSectors.append(s) }
            }
            difat = rdU32(sec, (perSector - 1) * 4)
            guardCount += 1
        }

        for s in fatSectors {
            guard let sec = sector(s) else { continue }
            for i in 0..<(sectorSize / 4) {
                fat.append(rdU32(sec, i * 4))
            }
        }

        // Каталог
        let dirBytes = readChain(start: dirStart)
        var idx = 0
        while idx + 128 <= dirBytes.count {
            let nameLen = rdU16(dirBytes, idx + 0x40)
            let type = Int(dirBytes[idx + 0x42])
            var units: [UInt16] = []
            let n = max(0, min(nameLen, 64) - 2)
            var p = 0
            while p + 2 <= n {
                let u = UInt16(dirBytes[idx + p]) | (UInt16(dirBytes[idx + p + 1]) << 8)
                units.append(u)
                p += 2
            }
            let name = String(decoding: units, as: UTF16.self)
            let start = rdU32(dirBytes, idx + 0x74)
            let size = rdU32(dirBytes, idx + 0x78)
            entries.append(Entry(name: name, type: type, start: start, size: size))
            idx += 128
        }

        // Мини-поток
        if let root = entries.first, root.type == 5 {
            var ms = readChain(start: root.start)
            if ms.count > root.size { ms = Array(ms[0..<root.size]) }
            miniStream = ms
        }
        let miniFatBytes = readChain(start: miniFatStart)
        var q = 0
        while q + 4 <= miniFatBytes.count {
            miniFat.append(rdU32(miniFatBytes, q))
            q += 4
        }
    }

    private func sector(_ n: Int) -> [UInt8]? {
        if n < 0 { return nil }
        let start = (n + 1) * sectorSize
        if start >= data.count { return nil }
        let end = min(start + sectorSize, data.count)
        var out = Array(data[start..<end])
        if out.count < sectorSize {
            out.append(contentsOf: [UInt8](repeating: 0, count: sectorSize - out.count))
        }
        return out
    }

    private func readChain(start: Int) -> [UInt8] {
        var out: [UInt8] = []
        var s = start
        var steps = 0
        while s < CFB.endOfChain && steps <= fat.count + 1 {
            guard let sec = sector(s) else { break }
            out.append(contentsOf: sec)
            if s >= fat.count { break }
            s = fat[s]
            steps += 1
        }
        return out
    }

    private func readMiniChain(start: Int, size: Int) -> [UInt8] {
        var out: [UInt8] = []
        var s = start
        var steps = 0
        while s < CFB.endOfChain && steps <= miniFat.count + 1 {
            let from = s * miniSectorSize
            if from >= miniStream.count { break }
            let to = min(from + miniSectorSize, miniStream.count)
            out.append(contentsOf: miniStream[from..<to])
            if s >= miniFat.count { break }
            s = miniFat[s]
            steps += 1
            if out.count >= size { break }
        }
        if out.count > size { out = Array(out[0..<size]) }
        return out
    }

    func stream(named names: [String]) -> [UInt8]? {
        let wanted = names.map { $0.lowercased() }
        guard let e = entries.first(where: { $0.type == 2 && wanted.contains($0.name.lowercased()) }) else {
            return nil
        }
        if e.size < miniCutoff {
            return readMiniChain(start: e.start, size: e.size)
        }
        var bytes = readChain(start: e.start)
        if bytes.count > e.size { bytes = Array(bytes[0..<e.size]) }
        return bytes
    }
}
