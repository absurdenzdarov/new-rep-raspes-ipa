import Foundation

@inline(__always) func rdU16(_ b: [UInt8], _ o: Int) -> Int {
    if o < 0 || o + 2 > b.count { return 0 }
    return Int(b[o]) | (Int(b[o + 1]) << 8)
}

@inline(__always) func rdU32(_ b: [UInt8], _ o: Int) -> Int {
    if o < 0 || o + 4 > b.count { return 0 }
    let a = Int(b[o])
    let b1 = Int(b[o + 1]) << 8
    let c = Int(b[o + 2]) << 16
    let d = Int(b[o + 3]) << 24
    return a | b1 | c | d
}

func rdDouble(_ b: [UInt8], _ o: Int) -> Double {
    if o < 0 || o + 8 > b.count { return 0 }
    var v: UInt64 = 0
    for i in 0..<8 {
        v |= UInt64(b[o + i]) << UInt64(8 * i)
    }
    return Double(bitPattern: v)
}

func numString(_ d: Double) -> String {
    if d.isFinite && d == d.rounded() && abs(d) < 1e15 {
        return String(Int64(d))
    }
    return String(d)
}
