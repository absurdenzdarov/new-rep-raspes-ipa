import Foundation
import PDFKit

/// Учебный график — PDF на сайте колледжа. Ссылка меняется каждый год,
/// поэтому ищем её прямо на странице (та же логика, что в боте).
@MainActor
final class CalendarStore: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var document: PDFDocument?
    @Published private(set) var sourceURL: String?
    @Published private(set) var data: CalendarData?
    @Published private(set) var statusText: String = "Загружаю учебный график…"

    private static let maxAge: TimeInterval = 24 * 3600

    private func cacheURL() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("academic-calendar.pdf")
    }

    private func parsedURL() -> URL {
        return cacheURL().deletingLastPathComponent().appendingPathComponent("academic-calendar-parsed.json")
    }

    private struct ParsedCache: Codable {
        var hash: String
        var version: Int
        var data: CalendarData
    }

    private static let parserVersion = 1

    func load(pageURL: String, force: Bool = false) async {
        if state == .loading { return }
        if !force, data != nil || document != nil, state == .ready { return }
        state = .loading
        statusText = "Ищу учебный график на сайте…"

        let cache = cacheURL()
        var pdfData: Data? = nil

        let fresh: Bool = {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: cache.path),
                  let modified = attrs[.modificationDate] as? Date else { return false }
            return Date().timeIntervalSince(modified) < CalendarStore.maxAge
        }()

        if !force && fresh {
            pdfData = try? Data(contentsOf: cache)
        }

        if pdfData == nil {
            do {
                let pdfURL = try await CalendarStore.findPDFURL(pageURL: pageURL)
                statusText = "Скачиваю PDF…"
                let (downloaded, _) = try await URLSession.shared.data(from: pdfURL)
                guard downloaded.prefix(5) == Data("%PDF-".utf8) else {
                    throw SyncError.network("по ссылке лежит не PDF")
                }
                try? downloaded.write(to: cache, options: .atomic)
                sourceURL = pdfURL.absoluteString
                pdfData = downloaded
            } catch {
                // Нет сети — используем сохранённую копию, если она есть
                pdfData = try? Data(contentsOf: cache)
                if pdfData == nil {
                    state = .failed(error.localizedDescription)
                    return
                }
            }
        }

        guard let bytes = pdfData, let doc = PDFDocument(data: bytes) else {
            state = .failed("не удалось открыть PDF")
            return
        }
        document = doc

        // Уже разобранный график для этого же файла — берём из кэша
        let hash = md5Hex(bytes)
        if let cached = try? Data(contentsOf: parsedURL()),
           let parsed = try? JSONDecoder().decode(ParsedCache.self, from: cached),
           parsed.hash == hash, parsed.version == CalendarStore.parserVersion {
            data = parsed.data
            state = .ready
            return
        }

        statusText = "Разбираю таблицу графика…"
        let result: CalendarData? = await Task.detached(priority: .userInitiated) {
            return CalendarParser.parse(data: bytes)
        }.value
        data = result
        if let r = result, !r.groups.isEmpty {
            let payload = ParsedCache(hash: hash, version: CalendarStore.parserVersion, data: r)
            if let enc = try? JSONEncoder().encode(payload) {
                try? enc.write(to: parsedURL(), options: .atomic)
            }
        }
        state = .ready
    }

    private static func findPDFURL(pageURL: String) async throws -> URL {
        guard let base = URL(string: pageURL) else { throw SyncError.network("неверный адрес страницы графика") }
        let (data, _) = try await URLSession.shared.data(from: base)
        let html = String(decoding: data, as: UTF8.self)

        guard let re = try? NSRegularExpression(pattern: "href=\"([^\"]+\\.pdf)\"[^>]*>([^<]*)",
                                                options: [.caseInsensitive]) else {
            throw SyncError.network("не удалось разобрать страницу")
        }
        var candidates: [(String, String)] = []
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            if m.numberOfRanges >= 3 {
                candidates.append((ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2))))
            }
        }
        if let bare = try? NSRegularExpression(pattern: "href=\"([^\"]+\\.pdf)\"", options: [.caseInsensitive]) {
            for m in bare.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                let u = ns.substring(with: m.range(at: 1))
                if !candidates.contains(where: { $0.0 == u }) { candidates.append((u, "")) }
            }
        }
        if candidates.isEmpty { throw SyncError.network("на странице нет ссылки на PDF") }

        let negative = ["трудоустройств", "вакан", "работодател", "банк", "заявк", "стипенд"]
        func score(_ c: (String, String)) -> Int {
            let combined = (c.0 + " " + c.1).lowercased()
            if combined.contains("kug") || combined.contains("график") { return 0 }
            if negative.contains(where: { combined.contains($0) }) { return 2 }
            return 1
        }
        let best = candidates.enumerated().sorted { a, b in
            let sa = score(a.element)
            let sb = score(b.element)
            if sa != sb { return sa < sb }
            return a.offset < b.offset
        }.first?.element

        guard let raw = best?.0 else { throw SyncError.network("ссылка на график не найдена") }
        var link = raw
        if link.hasPrefix("//") { link = "https:" + link }
        guard let url = URL(string: link, relativeTo: base)?.absoluteURL else {
            throw SyncError.network("неверная ссылка на график")
        }
        return url
    }
}
