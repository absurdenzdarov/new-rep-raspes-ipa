import Foundation
import SwiftUI

private struct CachePayload: Codable {
    var lessons: [Lesson]
    var signature: String?
    var updatedAt: Date
}

private struct Slot {
    var name: String
    var date: Date
    var lesson: Lesson
    var groups: Set<String>
}

@MainActor
final class ScheduleStore: ObservableObject {
    static let defaultLink = "https://disk.360.yandex.ru/d/Xc08g8WbTavdHQ"
    static let defaultCalendarPage = "https://mck72.ru/learners/information-on-learning-process/schedule-of-educational-process/"

    @Published private(set) var lessons: [Lesson] = []
    @Published private(set) var names: [SearchKind: [String]] = [:]
    @Published private(set) var weekStarts: [Date] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastChecked: Date?
    @Published var errorMessage: String?
    @Published private(set) var gate: GateState = .loading
    @Published private(set) var progress = SyncProgress(fraction: 0.02, message: "Подключаюсь…")

    @Published var favorites: [Entity] {
        didSet { saveJSON(favorites, key: "favorites.v2") }
    }
    @Published var selected: Entity? {
        didSet { saveJSON(selected, key: "selected.v2") }
    }
    @Published var publicLink: String {
        didSet { UserDefaults.standard.set(publicLink, forKey: "publicLink") }
    }
    @Published var calendarPage: String {
        didSet { UserDefaults.standard.set(calendarPage, forKey: "calendarPage") }
    }

    private var indexes: [SearchKind: [String: [Date: [DayEntry]]]] = [:]
    private var teacherSubjects: [String: [String]] = [:]
    private var daysWithData: Set<Date> = []
    private var mealByGroup: [String: String] = [:]
    private var signature: String?

    init() {
        let d = UserDefaults.standard
        publicLink = d.string(forKey: "publicLink") ?? ScheduleStore.defaultLink
        calendarPage = d.string(forKey: "calendarPage") ?? ScheduleStore.defaultCalendarPage

        var favs: [Entity] = []
        if let data = d.data(forKey: "favorites.v2"),
           let decoded = try? JSONDecoder().decode([Entity].self, from: data) {
            favs = decoded
        } else if let old = d.stringArray(forKey: "subscriptions") {
            favs = old.map { Entity(kind: .group, name: $0) }
        }
        favorites = favs

        var sel: Entity? = nil
        if let data = d.data(forKey: "selected.v2"),
           let decoded = try? JSONDecoder().decode(Entity.self, from: data) {
            sel = decoded
        } else if let g = d.string(forKey: "selectedGroup") {
            sel = Entity(kind: .group, name: g)
        }
        selected = sel

        loadMeals()
        loadCache()
        if selected == nil { selected = favorites.first }
    }

    // MARK: - Запросы

    func entries(_ e: Entity, on day: Date) -> [DayEntry] {
        return indexes[e.kind]?[e.name]?[day] ?? []
    }

    func hasLessons(_ e: Entity, on day: Date) -> Bool {
        return !(indexes[e.kind]?[e.name]?[day]?.isEmpty ?? true)
    }

    func meal(for e: Entity) -> String? {
        return e.kind == .group ? mealByGroup[e.name] : nil
    }

    func lessonsCount(_ e: Entity) -> Int {
        var n = 0
        for (_, v) in indexes[e.kind]?[e.name] ?? [:] { n += v.count }
        return n
    }

    func subjects(forTeacher name: String) -> [String] {
        return teacherSubjects[name] ?? []
    }

    func list(_ kind: SearchKind) -> [String] {
        return names[kind] ?? []
    }

    func isFavorite(_ e: Entity) -> Bool {
        return favorites.contains(e)
    }

    func toggleFavorite(_ e: Entity) {
        if let i = favorites.firstIndex(of: e) {
            favorites.remove(at: i)
        } else {
            favorites.append(e)
            if selected == nil { selected = e }
        }
    }

    func select(_ e: Entity) {
        selected = e
    }

    // MARK: - Кабинеты и корпуса

    static func corpus(of room: String) -> String? {
        let t = room.trimmingCharacters(in: .whitespaces)
        guard let slash = t.lastIndex(of: "/") else { return nil }
        let head = t[t.startIndex..<slash]
        let tail = t[t.index(after: slash)...]
        if head.isEmpty || tail.isEmpty { return nil }
        if !tail.allSatisfy({ $0.isNumber }) { return nil }
        return String(tail)
    }

    var corpuses: [String] {
        var set = Set<String>()
        for r in list(.room) {
            if let c = ScheduleStore.corpus(of: r) { set.insert(c) }
        }
        return set.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Свободные прямо сейчас кабинеты корпуса. hasData == false, если на сегодня в базе пусто.
    func freeRooms(corpus: String, now: Date) -> (rooms: [String], hasData: Bool) {
        let today = AppTime.startOfDay(now)
        if !daysWithData.contains(today) { return ([], false) }
        let nowMin = Int(AppTime.minutesFloat(now))
        var free: [String] = []
        for room in list(.room) where ScheduleStore.corpus(of: room) == corpus {
            let todays = indexes[.room]?[room]?[today] ?? []
            var busy = false
            for e in todays {
                if let r = TimeParsing.range(e.lesson.time), r.0 <= nowMin, nowMin < r.1 {
                    busy = true
                    break
                }
            }
            if !busy { free.append(room) }
        }
        return (free, true)
    }

    // MARK: - Обновление

    func dismissGate() {
        gate = .hidden
    }

    func refresh(force: Bool = false) async {
        if isRefreshing { return }
        if !force, let c = lastChecked, Date().timeIntervalSince(c) < 60 {
            if gate == .loading { gate = .hidden }
            return
        }
        isRefreshing = true
        errorMessage = nil
        gate = .loading
        progress = SyncProgress(fraction: 0.02, message: "Подключаюсь к Яндекс.Диску…")
        let started = Date()
        let link = publicLink
        let sig: String? = (force || lessons.isEmpty) ? nil : signature
        var failure: String? = nil

        do {
            let result = try await SyncEngine.sync(link: link, knownSignature: sig) { [weak self] p in
                Task { @MainActor in
                    self?.progress = p
                }
            }
            switch result {
            case .unchanged:
                break
            case .updated(let newLessons, let newSig):
                apply(lessons: newLessons, signature: newSig, updatedAt: Date())
                saveCache()
            }
        } catch {
            failure = error.localizedDescription
        }

        // Минимальное время показа загрузки — чтобы анимация не мигала
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < 1.8 {
            try? await Task.sleep(nanoseconds: UInt64((1.8 - elapsed) * 1_000_000_000))
        }

        if let f = failure {
            errorMessage = f
            gate = .failed(f)
        } else {
            lastChecked = Date()
            progress = SyncProgress(fraction: 1, message: "Готово")
            try? await Task.sleep(nanoseconds: 450_000_000)
            gate = .hidden
        }
        isRefreshing = false
    }

    func setLink(_ link: String) async {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        publicLink = trimmed.isEmpty ? ScheduleStore.defaultLink : trimmed
        await refresh(force: true)
    }

    func clearCache() {
        YandexDiskClient.clearCache()
        try? FileManager.default.removeItem(at: cacheURL())
        signature = nil
        lastUpdated = nil
        lastChecked = nil
        apply(lessons: [], signature: nil, updatedAt: nil)
    }

    // MARK: - Индексы

    private func apply(lessons newLessons: [Lesson], signature newSig: String?, updatedAt: Date?) {
        lessons = newLessons
        signature = newSig
        lastUpdated = updatedAt
        rebuild()
    }

    private static func isBlank(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "." || t == "-" || t == "—"
    }

    private static func addSlot(_ slots: inout [String: Slot], _ order: inout [String],
                                name: String, date: Date, lesson: Lesson) {
        let key = [name, lesson.dayStr, lesson.num, lesson.subject, lesson.teacher, lesson.room].joined(separator: "|")
        if var s = slots[key] {
            s.groups.insert(lesson.group)
            slots[key] = s
        } else {
            slots[key] = Slot(name: name, date: date, lesson: lesson, groups: [lesson.group])
            order.append(key)
        }
    }

    private func rebuild() {
        var groupIdx: [String: [Date: [DayEntry]]] = [:]
        var mondays = Set<Date>()
        var days = Set<Date>()
        var groupSet = Set<String>()

        // Потоки: одинаковые день/пара/предмет/преподаватель/кабинет у нескольких групп
        var streams: [String: Set<String>] = [:]
        for l in lessons where !l.subject.isEmpty && !l.teacher.isEmpty && !l.room.isEmpty {
            let k = [l.dayStr, l.num, l.subject, l.teacher, l.room].joined(separator: "|")
            streams[k, default: []].insert(l.group)
        }

        var tSlots: [String: Slot] = [:]
        var tOrder: [String] = []
        var rSlots: [String: Slot] = [:]
        var rOrder: [String] = []

        for l in lessons {
            groupSet.insert(l.group)
            guard let d = DayParsing.date(from: l.dayStr) else { continue }
            days.insert(d)
            mondays.insert(AppTime.monday(of: d))

            // Группа
            let sk = [l.dayStr, l.num, l.subject, l.teacher, l.room].joined(separator: "|")
            let mates = (streams[sk] ?? []).filter { $0 != l.group }.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
            groupIdx[l.group, default: [:]][d, default: []].append(DayEntry(lesson: l, groups: mates))

            // Преподаватели и кабинеты — без «СЕССИЯ»/«ГИА»
            let statusKey = l.subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if Presenter.statuses[statusKey] != nil { continue }

            let subs = Presenter.lines(l.subject)
            let teachers = Presenter.lines(l.teacher)
            let rooms = Presenter.lines(l.room)

            if Presenter.isGenuineElective(l.subject) {
                for (i, s) in subs.enumerated() {
                    let t: String = i < teachers.count ? teachers[i] : (teachers.count == 1 ? teachers[0] : "")
                    let r: String = i < rooms.count ? rooms[i] : (rooms.count == 1 ? rooms[0] : "")
                    var copy = l
                    copy.subject = s
                    copy.teacher = t
                    copy.room = r
                    if !ScheduleStore.isBlank(t) {
                        ScheduleStore.addSlot(&tSlots, &tOrder, name: t, date: d, lesson: copy)
                    }
                    if !ScheduleStore.isBlank(r) {
                        ScheduleStore.addSlot(&rSlots, &rOrder, name: r, date: d, lesson: copy)
                    }
                }
            } else {
                for t in teachers where !ScheduleStore.isBlank(t) {
                    var copy = l
                    copy.teacher = t
                    ScheduleStore.addSlot(&tSlots, &tOrder, name: t, date: d, lesson: copy)
                }
                for r in rooms where !ScheduleStore.isBlank(r) {
                    var copy = l
                    copy.room = r
                    ScheduleStore.addSlot(&rSlots, &rOrder, name: r, date: d, lesson: copy)
                }
            }
        }

        func fill(_ order: [String], _ slots: [String: Slot]) -> [String: [Date: [DayEntry]]] {
            var idx: [String: [Date: [DayEntry]]] = [:]
            for key in order {
                guard let s = slots[key] else { continue }
                let g = s.groups.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                idx[s.name, default: [:]][s.date, default: []].append(DayEntry(lesson: s.lesson, groups: g))
            }
            return idx
        }

        let teacherIdx = fill(tOrder, tSlots)
        let roomIdx = fill(rOrder, rSlots)

        var subjectsByTeacher: [String: Set<String>] = [:]
        for key in tOrder {
            guard let s = tSlots[key] else { continue }
            for sub in Presenter.lines(s.lesson.subject) {
                subjectsByTeacher[s.name, default: []].insert(sub)
            }
        }

        func sortedNames(_ set: Set<String>) -> [String] {
            return set.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }

        indexes = [.group: groupIdx, .teacher: teacherIdx, .room: roomIdx]
        teacherSubjects = subjectsByTeacher.mapValues { $0.sorted() }
        daysWithData = days
        weekStarts = mondays.sorted()
        names = [
            .group: sortedNames(groupSet),
            .teacher: sortedNames(Set(teacherIdx.keys)),
            .room: sortedNames(Set(roomIdx.keys))
        ]
    }

    // MARK: - Диск

    private func saveJSON<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func cacheURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("lessons-cache.json")
    }

    private func saveCache() {
        let payload = CachePayload(lessons: lessons, signature: signature, updatedAt: lastUpdated ?? Date())
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: cacheURL(), options: .atomic)
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL()),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data) else { return }
        apply(lessons: payload.lessons, signature: payload.signature, updatedAt: payload.updatedAt)
    }

    private func loadMeals() {
        guard let url = Bundle.main.url(forResource: "meals", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([MealEntry].self, from: data) else { return }
        var map: [String: String] = [:]
        for e in entries {
            for g in e.groups where map[g] == nil {
                map[g] = e.time
            }
        }
        mealByGroup = map
    }
}
