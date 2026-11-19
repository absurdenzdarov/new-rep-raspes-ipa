import Foundation

struct ElectiveOption: Hashable {
    let subject: String
    let teacher: String
    let room: String
}

struct LessonItem: Identifiable {
    enum Kind {
        case regular
        case elective([ElectiveOption])
        case status(String)
        case meal
    }

    let id: String
    let numLabel: String
    let time: String
    let start: Int?
    let end: Int?
    let subject: String
    let teacher: String
    let room: String
    let groups: [String]
    let kind: Kind

    var isReal: Bool {
        switch kind {
        case .regular, .elective: return true
        default: return false
        }
    }
}

struct MealEntry: Codable {
    let shift: String
    let time: String
    let groups: [String]
}

enum Presenter {
    static let statuses: [String: String] = [
        "сессия": "СЕССИЯ",
        "гиа": "ГИА — государственная итоговая аттестация"
    ]

    static let nonElective: Set<String> = [
        "классный час", "разговоры о важном", "орг.час", "оргчас", "классный  час"
    ]

    static func lines(_ s: String) -> [String] {
        return s.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func isGenuineElective(_ s: String) -> Bool {
        let opts = lines(s)
        if opts.count < 2 || Set(opts).count < 2 { return false }
        if opts.contains(where: { nonElective.contains($0.lowercased()) }) { return false }
        return true
    }

    private struct Acc {
        var lesson: Lesson
        var groups: [String]
        var firstNum: Int?
        var lastNum: Int?
        var firstTime: String
        var span: Bool
    }

    static func items(for entries: [DayEntry], meal: String?) -> [LessonItem] {
        let sorted = entries.sorted { a, b in
            let sa = TimeParsing.range(a.lesson.time)?.0 ?? 99999
            let sb = TimeParsing.range(b.lesson.time)?.0 ?? 99999
            if sa != sb { return sa < sb }
            return a.lesson.num < b.lesson.num
        }

        // Электив, объединённый на несколько пар подряд, сворачиваем в одну карточку
        var accs: [Acc] = []
        for e in sorted {
            let l = e.lesson
            if var prev = accs.last,
               isGenuineElective(l.subject),
               prev.lesson.subject == l.subject,
               prev.lesson.teacher == l.teacher,
               prev.lesson.room == l.room,
               let n = Int(l.num),
               let pl = prev.lastNum,
               n == pl + 1 {
                prev.lastNum = n
                prev.span = true
                let startStr = TimeParsing.split(prev.firstTime)?.0 ?? prev.firstTime
                let endStr = TimeParsing.split(l.time)?.1 ?? l.time
                prev.lesson.time = "\(startStr)–\(endStr)"
                accs[accs.count - 1] = prev
            } else {
                accs.append(Acc(lesson: l, groups: e.groups, firstNum: Int(l.num), lastNum: Int(l.num),
                                firstTime: l.time, span: false))
            }
        }

        var out: [LessonItem] = []
        for a in accs {
            let l = a.lesson
            let r = TimeParsing.range(l.time)
            let numLabel: String
            if l.num.hasPrefix("орг") {
                numLabel = ""
            } else if a.span, let f = a.firstNum, let la = a.lastNum {
                numLabel = "\(f)–\(la) пары"
            } else {
                numLabel = "\(l.num) пара"
            }
            let key = l.subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let kind: LessonItem.Kind
            if let label = statuses[key] {
                kind = .status(label)
            } else if isGenuineElective(l.subject) {
                let subs = lines(l.subject)
                let teachers = lines(l.teacher)
                let rooms = lines(l.room)
                var opts: [ElectiveOption] = []
                for (i, s) in subs.enumerated() {
                    opts.append(ElectiveOption(subject: s,
                                               teacher: i < teachers.count ? teachers[i] : "",
                                               room: i < rooms.count ? rooms[i] : ""))
                }
                kind = .elective(opts)
            } else {
                kind = .regular
            }
            out.append(LessonItem(id: l.id + (a.span ? "#span" : ""),
                                  numLabel: numLabel, time: l.time,
                                  start: r?.0, end: r?.1,
                                  subject: l.subject, teacher: l.teacher, room: l.room,
                                  groups: a.groups,
                                  kind: kind))
        }

        // Обед: не в субботу, не в день сессии и не в день с элективом
        if let meal = meal, let first = entries.first?.lesson {
            let isSaturday = first.dayStr.lowercased().contains("суббота")
            let allStatuses = !out.isEmpty && out.allSatisfy { (item: LessonItem) -> Bool in
                if case .status = item.kind { return true }
                return false
            }
            let hasElective = out.contains { (item: LessonItem) -> Bool in
                if case .elective = item.kind { return true }
                return false
            }
            if !isSaturday && !allStatuses && !hasElective {
                let r = TimeParsing.range(meal)
                let item = LessonItem(id: "meal|" + meal, numLabel: "", time: meal,
                                      start: r?.0, end: r?.1, subject: "Обед", teacher: "", room: "",
                                      groups: [], kind: .meal)
                let ms = r?.0 ?? 99999
                let idx = out.firstIndex(where: { ($0.start ?? 99999) > ms }) ?? out.count
                out.insert(item, at: idx)
            }
        }
        return out
    }

    struct LiveState {
        var current: LessonItem?
        var next: LessonItem?
        var finished: Bool
    }

    static func live(items: [LessonItem], now: Double) -> LiveState {
        let real = items.filter { $0.isReal && $0.start != nil && $0.end != nil }
        if let cur = real.first(where: { Double($0.start ?? 0) <= now && now < Double($0.end ?? 0) }) {
            let next = real.first(where: { Double($0.start ?? 0) >= Double(cur.end ?? 0) })
            return LiveState(current: cur, next: next, finished: false)
        }
        if let next = real.first(where: { Double($0.start ?? 0) > now }) {
            return LiveState(current: nil, next: next, finished: false)
        }
        return LiveState(current: nil, next: nil, finished: !real.isEmpty)
    }

    /// Строка статуса для сегодняшнего дня: «Сейчас…», «Следующая пара через…»
    static func statusLine(items: [LessonItem], now: Double) -> String? {
        let real = items.filter { $0.isReal && $0.start != nil && $0.end != nil }
        if real.isEmpty { return nil }
        if let cur = real.first(where: { Double($0.start ?? 0) <= now && now < Double($0.end ?? 0) }) {
            let left = Int((Double(cur.end ?? 0) - now).rounded(.up))
            return "Идёт пара · до конца \(RU.humanMinutes(left))"
        }
        if let next = real.first(where: { Double($0.start ?? 0) > now }) {
            let left = Int((Double(next.start ?? 0) - now).rounded(.up))
            return "Следующая пара через \(RU.humanMinutes(left))"
        }
        return "Занятия на сегодня закончились"
    }

    static func summary(items: [LessonItem]) -> String? {
        let real = items.filter { $0.isReal }
        if real.isEmpty { return nil }
        let starts = real.compactMap { $0.start }
        let ends = real.compactMap { $0.end }
        let count = real.count
        var text = "\(count) \(RU.plural(count, "занятие", "занятия", "занятий"))"
        if let s = starts.min(), let e = ends.max() {
            text += " · \(clock(s))–\(clock(e))"
        }
        return text
    }

    static func clock(_ m: Int) -> String {
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    static func stableHash(_ s: String) -> Int {
        var h = 5381
        for u in s.unicodeScalars {
            h = (h &* 33) &+ Int(u.value)
        }
        return abs(h == Int.min ? 0 : h)
    }
}
