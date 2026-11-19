import Foundation

/// Порт разбора расписания из Telegram-бота: те же правила чтения листа,
/// объединённых ячеек, дней недели, дедупликации и «почти-дублей».
enum ScheduleParser {

    // MARK: - Публичный API

    static func parse(_ sheets: [RawSheet]) -> [Lesson] {
        var out: [Lesson] = []
        for s in sheets {
            out.append(contentsOf: parseSheet(s))
        }
        return out
    }

    static func finalize(_ builder: [Lesson]) -> [Lesson] {
        // 1. Точные дубли
        var seen = Set<String>()
        var deduped: [Lesson] = []
        for l in builder {
            if seen.insert(l.id).inserted { deduped.append(l) }
        }

        // 2. «Почти-дубли» одного слота день+группа+номер пары
        var slotBest: [String: Lesson] = [:]
        var slotOrder: [String] = []
        var result: [Lesson] = []

        for l in deduped {
            if l.num.hasPrefix("орг") || l.group.isEmpty {
                result.append(l)
                continue
            }
            let key = [l.dayStr, l.group, l.num].joined(separator: "|")
            guard let existing = slotBest[key] else {
                slotBest[key] = l
                slotOrder.append(key)
                continue
            }
            let eE = Presenter.isGenuineElective(existing.subject)
            let lE = Presenter.isGenuineElective(l.subject)
            if eE && !lE { continue }
            if lE && !eE {
                slotBest[key] = l
                continue
            }
            if existing.subject == l.subject && existing.teacher == l.teacher {
                if isPlaceholder(existing.room) && !isPlaceholder(l.room) {
                    slotBest[key] = l
                }
            } else {
                result.append(l)
            }
        }
        for k in slotOrder {
            if let l = slotBest[k] { result.append(l) }
        }
        return result
    }

    private static func isPlaceholder(_ r: String) -> Bool {
        let t = r.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "." || t == "-" || t == "—"
    }

    // MARK: - Сетка листа

    static func buildGrid(_ sheet: RawSheet) -> [[String]] {
        var cells = sheet.cells
        var maxRow = -1
        var maxCol = -1
        for (r, cols) in cells {
            if r > maxRow { maxRow = r }
            for c in cols.keys where c > maxCol { maxCol = c }
        }
        if maxRow < 0 { return [] }
        for m in sheet.merges {
            if m.c1 <= 300 && m.c1 > maxCol { maxCol = m.c1 }
        }

        // Раскрываем объединённые ячейки: значение верхней левой — во все ячейки диапазона
        for m in sheet.merges {
            guard let top = cells[m.r0]?[m.c0], !top.isEmpty else { continue }
            let r1 = min(m.r1, maxRow)
            let c1 = min(m.c1, maxCol)
            if m.r0 > r1 || m.c0 > c1 { continue }
            for r in m.r0...r1 {
                for c in m.c0...c1 {
                    cells[r, default: [:]][c] = top
                }
            }
        }

        // Ширина кратна тройке (предмет / преподаватель / кабинет)
        var width = maxCol + 1
        if width > 3 {
            let rem = (width - 3) % 3
            if rem != 0 { width += 3 - rem }
        }

        var grid: [[String]] = []
        grid.reserveCapacity(maxRow + 1)
        for r in 0...maxRow {
            let rowCells = cells[r]
            var row: [String] = []
            row.reserveCapacity(width)
            for c in 0..<width {
                row.append(rowCells?[c] ?? "")
            }
            grid.append(row)
        }
        return grid
    }

    // MARK: - Разбор листа

    static func parseSheet(_ sheet: RawSheet) -> [Lesson] {
        let rows = buildGrid(sheet)
        if rows.isEmpty { return [] }
        let ws = CharacterSet.whitespacesAndNewlines

        // Строка-заголовок с названиями групп
        var header: [String] = rows[0]
        for r in rows {
            if let first = r.first, first.contains("День недели") {
                header = r
                break
            }
        }

        // День для каждой строки (пустая ячейка = тот же день, что выше)
        var dayByRow: [String] = []
        var currentDay = ""
        for row in rows {
            if let first = row.first {
                let t = first.trimmingCharacters(in: ws)
                if !t.isEmpty && !first.contains("День недели") {
                    currentDay = DayParsing.fixWeekdayTypo(t)
                }
            }
            dayByRow.append(currentDay)
        }
        if let firstDay = dayByRow.first(where: { !$0.isEmpty }) {
            for i in 0..<dayByRow.count {
                if !dayByRow[i].isEmpty { break }
                dayByRow[i] = firstDay
            }
        }

        var out: [Lesson] = []
        for (rowIdx, row) in rows.enumerated() {
            if row.count < 3 { continue }
            let day = dayByRow[rowIdx]
            var lessonNum = row[1].trimmingCharacters(in: ws)
            let lessonTime = row[2].trimmingCharacters(in: ws)
            if lessonTime.isEmpty || lessonNum.contains("№") { continue }
            if lessonNum.isEmpty {
                let start: String = TimeParsing.split(lessonTime)?.0 ?? lessonTime
                lessonNum = start.isEmpty ? "орг" : "орг\(start)"
            }

            var col = 3
            while col < row.count {
                if col + 2 >= row.count { break }
                let group = col < header.count ? header[col].trimmingCharacters(in: ws) : ""
                if group.isEmpty || group.contains("Фамилия") || group.contains("Каб") {
                    col += 3
                    continue
                }
                let subject = row[col].trimmingCharacters(in: ws)
                let teacher = row[col + 1].trimmingCharacters(in: ws)
                let room = row[col + 2].trimmingCharacters(in: ws)
                if !subject.isEmpty && subject.lowercased() != "гия" {
                    out.append(Lesson(dayStr: day, num: lessonNum, time: lessonTime, group: group,
                                      subject: subject, teacher: teacher, room: room))
                }
                col += 3
            }
        }
        return out
    }
}
