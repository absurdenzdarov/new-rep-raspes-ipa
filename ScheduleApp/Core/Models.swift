import Foundation

// MARK: - Данные

struct Lesson: Codable, Hashable, Identifiable {
    var dayStr: String
    var num: String
    var time: String
    var group: String
    var subject: String
    var teacher: String
    var room: String

    var id: String { [dayStr, group, num, subject, teacher, room].joined(separator: "|") }
}

struct MergeRange {
    var r0: Int
    var r1: Int
    var c0: Int
    var c1: Int
}

struct RawSheet {
    var name: String
    var cells: [Int: [Int: String]]
    var merges: [MergeRange]
}

enum ExcelError: LocalizedError {
    case unknownFormat
    case badContainer
    case noWorkbook

    var errorDescription: String? {
        switch self {
        case .unknownFormat: return "Неизвестный формат Excel-файла"
        case .badContainer: return "Не удалось открыть файл расписания"
        case .noWorkbook: return "В файле не найдена книга Excel"
        }
    }
}

// MARK: - Время (Тюмень, UTC+5)

enum AppTime {
    static let zone: TimeZone = TimeZone(secondsFromGMT: 5 * 3600) ?? TimeZone.current

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.firstWeekday = 2
        c.locale = Locale(identifier: "ru_RU")
        return c
    }()

    static func startOfDay(_ d: Date) -> Date {
        return calendar.startOfDay(for: d)
    }

    /// Понедельник = 0 ... Воскресенье = 6
    static func weekdayIndex(_ d: Date) -> Int {
        return (calendar.component(.weekday, from: d) + 5) % 7
    }

    static func monday(of d: Date) -> Date {
        let start = calendar.startOfDay(for: d)
        let wd = weekdayIndex(start)
        return calendar.date(byAdding: .day, value: -wd, to: start) ?? start
    }

    static func addDays(_ d: Date, _ n: Int) -> Date {
        return calendar.date(byAdding: .day, value: n, to: d) ?? d
    }

    static func isToday(_ d: Date, now: Date) -> Bool {
        return calendar.isDate(d, inSameDayAs: now)
    }

    static func dayNumber(_ d: Date) -> Int {
        return calendar.component(.day, from: d)
    }

    static func month(_ d: Date) -> Int {
        return calendar.component(.month, from: d)
    }

    static func minutesFloat(_ now: Date) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: now)
        let h = Double(c.hour ?? 0)
        let m = Double(c.minute ?? 0)
        let s = Double(c.second ?? 0)
        return h * 60 + m + s / 60
    }
}

// MARK: - Русские названия

enum RU {
    static let weekdays: [String] = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]
    static let weekdayShort: [String] = ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "ВС"]
    static let monthsGen: [String] = ["января", "февраля", "марта", "апреля", "мая", "июня",
                                      "июля", "августа", "сентября", "октября", "ноября", "декабря"]

    static func monthName(_ d: Date) -> String {
        let i = AppTime.month(d) - 1
        return (i >= 0 && i < monthsGen.count) ? monthsGen[i] : ""
    }

    static func dayMonth(_ d: Date) -> String {
        return "\(AppTime.dayNumber(d)) \(monthName(d))"
    }

    static func longDay(_ d: Date) -> String {
        return "\(weekdays[AppTime.weekdayIndex(d)]), \(dayMonth(d))"
    }

    /// "7–12 сентября" или "28 сентября – 3 октября"
    static func weekRange(monday: Date) -> String {
        let sat = AppTime.addDays(monday, 5)
        if AppTime.month(monday) == AppTime.month(sat) {
            return "\(AppTime.dayNumber(monday))–\(AppTime.dayNumber(sat)) \(monthName(sat))"
        }
        return "\(dayMonth(monday)) – \(dayMonth(sat))"
    }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m10 = n % 10
        let m100 = n % 100
        if m10 == 1 && m100 != 11 { return one }
        if m10 >= 2 && m10 <= 4 && !(m100 >= 12 && m100 <= 14) { return few }
        return many
    }

    static func humanMinutes(_ total: Int) -> String {
        if total >= 60 {
            let h = total / 60
            let m = total % 60
            return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин"
        }
        return "\(max(total, 1)) мин"
    }
}

// MARK: - Разбор строки дня ("Понедельник 07.09.26")

enum DayParsing {
    private static let dateRe: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "(\\d{2})\\.(\\d{2})\\.(\\d{2})")
    }()

    private static let typoRe: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "([А-Яа-яЁё]+)(\\s+)(\\d{2}\\.\\d{2}\\.\\d{2})")
    }()

    static func date(from dayStr: String) -> Date? {
        let ns = dayStr as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = dateRe.firstMatch(in: dayStr, range: full), m.numberOfRanges == 4 else { return nil }
        guard let d = Int(ns.substring(with: m.range(at: 1))),
              let mo = Int(ns.substring(with: m.range(at: 2))),
              let y = Int(ns.substring(with: m.range(at: 3))) else { return nil }
        if mo < 1 || mo > 12 || d < 1 || d > 31 { return nil }
        var comps = DateComponents()
        comps.year = 2000 + y
        comps.month = mo
        comps.day = d
        guard let date = AppTime.calendar.date(from: comps) else { return nil }
        return AppTime.calendar.startOfDay(for: date)
    }

    /// В Excel колледжа в названии дня бывают опечатки («Пянтица»).
    /// Если слово не настоящий день недели — берём день недели из самой даты.
    static func fixWeekdayTypo(_ s: String) -> String {
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = typoRe.firstMatch(in: s, range: full), m.numberOfRanges == 4 else { return s }
        let word = ns.substring(with: m.range(at: 1))
        let lowered = RU.weekdays.map { $0.lowercased() }
        if lowered.contains(word.lowercased()) { return s }
        guard let d = date(from: ns.substring(with: m.range(at: 3))) else { return s }
        var canonical = RU.weekdays[AppTime.weekdayIndex(d)]
        if word == word.uppercased() {
            canonical = canonical.uppercased()
        } else if let f = word.first, f.isLowercase {
            canonical = canonical.lowercased()
        }
        return ns.replacingCharacters(in: m.range(at: 1), with: canonical)
    }
}

// MARK: - Время пары ("08:10–09:40")

enum TimeParsing {
    static func minutes(_ s: String) -> Int? {
        let cleaned = String(s.filter { !$0.isWhitespace }).replacingOccurrences(of: ".", with: ":")
        let parts = cleaned.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    private static let separators: Set<Character> = ["-", "–", "—"]

    static func split(_ s: String) -> (String, String)? {
        let parts = s.split(maxSplits: 1) { separators.contains($0) }
        guard parts.count == 2 else { return nil }
        let a = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let b = String(parts[1]).trimmingCharacters(in: .whitespaces)
        return (a, b)
    }

    static func range(_ s: String) -> (Int, Int)? {
        if let (a, b) = split(s), let ma = minutes(a), let mb = minutes(b) {
            return (ma, mb)
        }
        if let m = minutes(s.trimmingCharacters(in: .whitespaces)) {
            return (m, m)
        }
        return nil
    }
}

// MARK: - Даты учебного графика

extension RU {
    static func year(_ d: Date) -> Int {
        return AppTime.calendar.component(.year, from: d)
    }

    static func dateFull(_ d: Date) -> String {
        return "\(dayMonth(d)) \(year(d))"
    }

    /// «25–31 марта 2027», «28 декабря 2026 – 9 января 2027»
    static func rangeHuman(_ a: Date, _ b: Date) -> String {
        let cal = AppTime.calendar
        if cal.isDate(a, inSameDayAs: b) { return dateFull(a) }
        let sameMonth = AppTime.month(a) == AppTime.month(b) && year(a) == year(b)
        if sameMonth {
            return "\(AppTime.dayNumber(a))–\(AppTime.dayNumber(b)) \(monthName(b)) \(year(b))"
        }
        return "\(dateFull(a)) – \(dateFull(b))"
    }

    static func numeric(_ d: Date) -> String {
        return String(format: "%02d.%02d.%04d", AppTime.dayNumber(d), AppTime.month(d), year(d))
    }

    static func rangeNumeric(_ a: Date, _ b: Date) -> String {
        if AppTime.calendar.isDate(a, inSameDayAs: b) { return numeric(a) }
        return "\(numeric(a)) – \(numeric(b))"
    }
}
