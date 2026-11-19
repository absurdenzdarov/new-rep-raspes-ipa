import Foundation

private func stripPrefix(_ name: String) -> String {
    if let i = name.lastIndex(of: ":") {
        return String(name[name.index(after: i)...])
    }
    return name
}

final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var inSI = false
    private var inT = false
    private var phoneticDepth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch stripPrefix(elementName) {
        case "si":
            inSI = true
            current = ""
        case "rPh":
            phoneticDepth += 1
        case "t":
            if inSI && phoneticDepth == 0 { inT = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inT { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch stripPrefix(elementName) {
        case "t":
            inT = false
        case "rPh":
            phoneticDepth -= 1
        case "si":
            strings.append(current)
            inSI = false
        default:
            break
        }
    }
}

final class SheetXMLParser: NSObject, XMLParserDelegate {
    private let shared: [String]
    var cells: [Int: [Int: String]] = [:]
    var merges: [MergeRange] = []

    private var ref = ""
    private var type = ""
    private var text = ""
    private var inlineText = ""
    private var inCell = false
    private var inV = false
    private var inT = false

    init(shared: [String]) {
        self.shared = shared
    }

    static func cellRef(_ s: String) -> (Int, Int)? {
        var col = 0
        var rowStr = ""
        for ch in s.unicodeScalars {
            if ch.value >= 65 && ch.value <= 90 {
                col = col * 26 + Int(ch.value - 64)
            } else if ch.value >= 97 && ch.value <= 122 {
                col = col * 26 + Int(ch.value - 96)
            } else if ch.value >= 48 && ch.value <= 57 {
                rowStr.unicodeScalars.append(ch)
            }
        }
        guard col > 0, let row = Int(rowStr), row > 0 else { return nil }
        return (row - 1, col - 1)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch stripPrefix(elementName) {
        case "c":
            ref = attributeDict["r"] ?? ""
            type = attributeDict["t"] ?? ""
            text = ""
            inlineText = ""
            inCell = true
        case "v":
            inV = true
        case "t":
            if inCell { inT = true }
        case "mergeCell":
            let r = attributeDict["ref"] ?? ""
            let parts = r.split(separator: ":").map { String($0) }
            if let a = parts.first, let (r0, c0) = SheetXMLParser.cellRef(a) {
                let b = parts.count > 1 ? parts[1] : a
                if let (r1, c1) = SheetXMLParser.cellRef(b) {
                    merges.append(MergeRange(r0: r0, r1: r1, c0: c0, c1: c1))
                }
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inV {
            text += string
        } else if inT {
            inlineText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch stripPrefix(elementName) {
        case "v":
            inV = false
        case "t":
            inT = false
        case "c":
            finishCell()
            inCell = false
        default:
            break
        }
    }

    private func finishCell() {
        var value = ""
        switch type {
        case "s":
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let i = Int(t), i >= 0, i < shared.count { value = shared[i] }
        case "inlineStr":
            value = inlineText
        case "str":
            value = text
        case "b":
            value = text.trimmingCharacters(in: .whitespaces) == "1" ? "TRUE" : "FALSE"
        case "e":
            value = ""
        default:
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let d = Double(t) {
                value = numString(d)
            } else {
                value = text
            }
        }
        if value.isEmpty { return }
        if let (r, c) = SheetXMLParser.cellRef(ref) {
            cells[r, default: [:]][c] = value
        }
    }
}

enum XLSXReader {
    static func read(_ data: Data) throws -> [RawSheet] {
        guard let zip = ZipArchive(data: data) else { throw ExcelError.badContainer }

        var shared: [String] = []
        if let d = zip.read("xl/sharedStrings.xml") {
            let p = SharedStringsParser()
            let xp = XMLParser(data: d)
            xp.delegate = p
            xp.parse()
            shared = p.strings
        }

        let prefix = "xl/worksheets/sheet"
        func number(_ n: String) -> Int {
            let core = n.dropFirst(prefix.count).dropLast(4)
            return Int(core) ?? 0
        }
        let sheetFiles = zip.names
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".xml") }
            .sorted { number($0) < number($1) }

        var sheets: [RawSheet] = []
        for file in sheetFiles {
            guard let d = zip.read(file) else { continue }
            let p = SheetXMLParser(shared: shared)
            let xp = XMLParser(data: d)
            xp.delegate = p
            xp.parse()
            sheets.append(RawSheet(name: file, cells: p.cells, merges: p.merges))
        }
        return sheets
    }
}

enum ExcelReader {
    static func read(_ data: Data) throws -> [RawSheet] {
        let head = [UInt8](data.prefix(4))
        if head.count >= 2 && head[0] == 0x50 && head[1] == 0x4B {
            return try XLSXReader.read(data)
        }
        if head.count >= 4 && head[0] == 0xD0 && head[1] == 0xCF && head[2] == 0x11 && head[3] == 0xE0 {
            return try XLSReader.read(data)
        }
        throw ExcelError.unknownFormat
    }
}
