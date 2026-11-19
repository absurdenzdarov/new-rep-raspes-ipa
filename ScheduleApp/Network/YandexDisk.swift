import Foundation
import CryptoKit

enum SyncError: LocalizedError {
    case rateLimited
    case noFiles
    case network(String)
    case failedFiles([String])

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "Яндекс.Диск просит подождать — попробуйте через пару минут"
        case .noFiles:
            return "На Диске не найдено ни одного файла Excel"
        case .network(let s):
            return "Нет связи: \(s)"
        case .failedFiles(let names):
            return "Не удалось прочитать файлы: \(names.joined(separator: ", "))"
        }
    }
}

struct YDItem: Decodable {
    let name: String?
    let path: String?
    let type: String?
    let md5: String?
}

private struct YDListing: Decodable {
    struct Embedded: Decodable {
        let items: [YDItem]?
    }
    let embedded: Embedded?

    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
    }
}

func md5Hex(_ data: Data) -> String {
    let digest = Insecure.MD5.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

final class YandexDiskClient {
    private let link: String
    private let session: URLSession
    private let base = "https://cloud-api.yandex.net/v1/disk/public/resources"
    private let excelExt: Set<String> = ["xls", "xlsx", "xlsm"]

    init(link: String) {
        self.link = link
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    private static let allowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func enc(_ s: String) -> String {
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private func get(_ urlString: String) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else { throw SyncError.network("неверный адрес") }
        var lastError: Error = SyncError.network("неизвестная ошибка")
        for attempt in 1...2 {
            do {
                let (data, resp) = try await session.data(from: url)
                guard let http = resp as? HTTPURLResponse else { throw SyncError.network("пустой ответ") }
                if http.statusCode == 429 { throw SyncError.rateLimited }
                return (data, http)
            } catch SyncError.rateLimited {
                throw SyncError.rateLimited
            } catch {
                lastError = error
                if attempt < 2 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            }
        }
        throw SyncError.network(lastError.localizedDescription)
    }

    private func listing(path: String?) async throws -> [YDItem] {
        var q = "\(base)?public_key=\(YandexDiskClient.enc(link))&limit=200"
        if let p = path { q += "&path=\(YandexDiskClient.enc(p))" }
        let (data, http) = try await get(q)
        if http.statusCode == 404 { throw SyncError.network("папка не найдена — проверьте ссылку") }
        guard http.statusCode == 200 else { throw SyncError.network("ответ сервера \(http.statusCode)") }
        let decoded = try JSONDecoder().decode(YDListing.self, from: data)
        return decoded.embedded?.items ?? []
    }

    private func collect(_ items: [YDItem], depth: Int) async throws -> [YDItem] {
        var files: [YDItem] = []
        var dirs: [YDItem] = []
        for it in items {
            let ext = ((it.name ?? "") as NSString).pathExtension.lowercased()
            if it.type == "file" && excelExt.contains(ext) {
                files.append(it)
            } else if it.type == "dir" {
                dirs.append(it)
            }
        }
        if depth >= 3 { return files }
        for d in dirs {
            guard let p = d.path else { continue }
            do {
                let sub = try await listing(path: p)
                files.append(contentsOf: try await collect(sub, depth: depth + 1))
            } catch SyncError.rateLimited {
                throw SyncError.rateLimited
            } catch {
                continue
            }
        }
        return files
    }

    /// Все Excel-файлы публичной папки (кроме версий «для преподавателей»).
    func listExcelFiles() async throws -> [YDItem] {
        let root = try await listing(path: nil)
        let all = try await collect(root, depth: 0)
        return all.filter { !($0.path ?? "").lowercased().contains("преподавател") }
    }

    // MARK: - Скачивание с кэшем по md5

    private static func cacheDir() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("xls", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cacheURL(path: String, md5: String) -> URL {
        let key = md5Hex(Data(path.utf8))
        return YandexDiskClient.cacheDir().appendingPathComponent("\(key)_\(md5).bin")
    }

    private static func looksLikeExcel(_ d: Data) -> Bool {
        let h = [UInt8](d.prefix(4))
        if h.count >= 2 && h[0] == 0x50 && h[1] == 0x4B { return true }
        if h.count >= 4 && h[0] == 0xD0 && h[1] == 0xCF && h[2] == 0x11 && h[3] == 0xE0 { return true }
        return false
    }

    /// Возвращает данные файла и признак того, что он реально скачивался из сети.
    func fileData(for item: YDItem) async throws -> (Data, Bool) {
        let path = item.path ?? ""
        let expected = (item.md5 ?? "").lowercased()

        if !expected.isEmpty {
            let url = cacheURL(path: path, md5: expected)
            if let cached = try? Data(contentsOf: url), YandexDiskClient.looksLikeExcel(cached) {
                return (cached, false)
            }
        }

        var lastError = "нет ответа"
        for attempt in 1...4 {
            do {
                let api = "\(base)/download?public_key=\(YandexDiskClient.enc(link))&path=\(YandexDiskClient.enc(path))"
                let (meta, _) = try await get(api)
                let obj = (try? JSONSerialization.jsonObject(with: meta)) as? [String: Any]
                if let err = obj?["error"] as? String, err == "TooManyRequestsError" {
                    throw SyncError.rateLimited
                }
                guard let href = obj?["href"] as? String else {
                    lastError = "нет ссылки для скачивания"
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000)
                    continue
                }
                let (content, http) = try await get(href)
                let md5ok = expected.isEmpty || md5Hex(content) == expected
                if http.statusCode == 200 && YandexDiskClient.looksLikeExcel(content) && md5ok {
                    if !expected.isEmpty {
                        try? content.write(to: cacheURL(path: path, md5: expected), options: .atomic)
                    }
                    return (content, true)
                }
                lastError = "плохой ответ (HTTP \(http.statusCode))"
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000)
            } catch SyncError.rateLimited {
                throw SyncError.rateLimited
            } catch {
                lastError = error.localizedDescription
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000)
            }
        }
        throw SyncError.network(lastError)
    }

    static func clearCache() {
        try? FileManager.default.removeItem(at: cacheDir())
    }
}

// MARK: - Синхронизация

enum SyncResult {
    case unchanged
    case updated(lessons: [Lesson], signature: String)
}

enum SyncEngine {
    static let parserVersion = "v2"

    static func sync(link: String, knownSignature: String?,
                     progress: @escaping @Sendable (SyncProgress) -> Void) async throws -> SyncResult {
        let client = YandexDiskClient(link: link)
        progress(SyncProgress(fraction: 0.04, message: "Ищу файлы расписания…"))
        let items = try await client.listExcelFiles()
        if items.isEmpty { throw SyncError.noFiles }

        let raw = items.map { "\($0.path ?? "")#\($0.md5 ?? "")" }.sorted().joined(separator: "\n")
        let signature = md5Hex(Data((parserVersion + "\n" + raw).utf8))
        if let known = knownSignature, known == signature {
            progress(SyncProgress(fraction: 0.9, message: "Данные актуальны"))
            return .unchanged
        }

        let total = items.count
        progress(SyncProgress(fraction: 0.1, message: "Найдено файлов: \(total)"))

        var all: [Lesson] = []
        var failed: [String] = []
        for (i, item) in items.enumerated() {
            let base = 0.1 + 0.8 * Double(i) / Double(total)
            let step = 0.8 / Double(total)
            progress(SyncProgress(fraction: base, message: "Загружаю файл \(i + 1) из \(total)"))
            do {
                let (data, downloaded) = try await client.fileData(for: item)
                progress(SyncProgress(fraction: base + step * 0.6, message: "Читаю расписание \(i + 1) из \(total)"))
                let sheets = try ExcelReader.read(data)
                all.append(contentsOf: ScheduleParser.parse(sheets))
                progress(SyncProgress(fraction: base + step, message: "Файл \(i + 1) готов"))
                if downloaded { try? await Task.sleep(nanoseconds: 700_000_000) }
            } catch SyncError.rateLimited {
                throw SyncError.rateLimited
            } catch {
                failed.append(item.name ?? item.path ?? "файл")
            }
        }
        if !failed.isEmpty { throw SyncError.failedFiles(failed) }
        progress(SyncProgress(fraction: 0.94, message: "Собираю общее расписание…"))
        let merged = ScheduleParser.finalize(all)
        return .updated(lessons: merged, signature: signature)
    }
}
