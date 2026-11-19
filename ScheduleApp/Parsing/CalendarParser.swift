import Foundation
import PDFKit

struct CalEvent {
    var group: String
    var week: Int
    var weekday: Int
    var kind: String
    var label: String
}

struct PageParse {
    var events: [CalEvent]
    var hasWeekRow: Bool
    var groups: Int
}

/// Разбор PDF «Календарный учебный график» по координатам символов.
/// Логика та же, что в боте (pdfplumber): строка недель 1–52, блоки по 6 строк (Пн–Сб)
/// на группу, коды «к», «па», «уп01» и т.д., затем склейка в периоды.
enum CalendarParser {

    private struct Row {
        var cy: Double
        var g: [Glyph]
        var synthetic: Bool = false
    }

    private struct NameWord {
        var t: String
        var cx: Double
        var cy: Double
        var h: Double
    }

    private static let badKeywords: [String] = [
        "отделение", "учебных", "групп", "специальност", "направлен",
        "ппкрс", "ппссз", "квалифицированн", "среднего звена", "профессионал"
    ]

    private static let legend: [String: String] = [
        "к": "Каникулы",
        "па": "Промежуточная аттестация (сессия)",
        "гиа": "Государственная итоговая аттестация",
        "пдп": "Преддипломная практика",
        "д": "Демонстрационный экзамен",
        "эм": "Экзамен по модулю",
        "эк": "Квалификационный экзамен",
        "кэ": "Квалификационный экзамен",
        "дэ": "Демонстрационный экзамен",
        "х": "Выходной день"
    ]

    // MARK: - Публичный вход

    static func parse(data: Data) -> CalendarData? {
        guard let doc = PDFDocument(data: data), doc.pageCount > 0 else { return nil }

        let firstText = doc.page(at: 0)?.string ?? ""
        var note = ""
        var startYear = findStartYear(firstText) ?? 0
        if startYear == 0 {
            let c = AppTime.calendar.dateComponents([.year, .month], from: Date())
            let y = c.year ?? 2026
            startYear = (c.month ?? 9) >= 7 ? y : y - 1
            note += "учебный год в PDF не найден, взят \(startYear)–\(startYear + 1); "
        }

        var events: [CalEvent] = []
        var pages = 0
        var withWeekRow = 0
        var groupsFound = 0
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            pages += 1
            let glyphs = PDFGlyphs.glyphs(of: page)
            if glyphs.count < 200 { continue }
            let r = parsePage(glyphs)
            if r.hasWeekRow { withWeekRow += 1 }
            groupsFound += r.groups
            events.append(contentsOf: r.events)
        }

        let groups = buildPeriods(events, startYear: startYear)
        note += "год \(startYear); страниц \(pages), со строкой недель \(withWeekRow), групп \(groupsFound), "
        note += "периодов \(groups.values.reduce(0) { $0 + $1.count })"
        return CalendarData(startYear: startYear, groups: groups, diagnostics: note)
    }

    // MARK: - Учебный год

    static func findStartYear(_ text: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: "(\\d{4})\\s*[-–—/]\\s*(\\d{4})") else { return nil }
        let ns = text as NSString
        var best: Int? = nil
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard m.numberOfRanges == 3,
                  let y1 = Int(ns.substring(with: m.range(at: 1))),
                  let y2 = Int(ns.substring(with: m.range(at: 2))) else { continue }
            if y2 != y1 + 1 { continue }
            let from = max(0, m.range.location - 40)
            let to = min(ns.length, m.range.location + m.range.length + 40)
            let near = ns.substring(with: NSRange(location: from, length: to - from)).lowercased()
            if near.contains("учебн") { return y1 }
            if best == nil { best = y1 }
        }
        return best
    }

    // MARK: - Классификация кода

    private static func classify(_ raw: String) -> (String, String)? {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty || v == "*" { return nil }
        let low = v.lowercased()
        if let l = legend[low] { return (low, l) }
        if low.hasPrefix("уп") {
            return ("уп", ("Учебная практика " + String(v.dropFirst(2))).trimmingCharacters(in: .whitespaces))
        }
        if low.hasPrefix("пп") {
            return ("пп", ("Производственная практика " + String(v.dropFirst(2))).trimmingCharacters(in: .whitespaces))
        }
        return (low, v)
    }

    private static func isGroupCode(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count < 2 || t.count > 25 { return false }
        if !t.contains(where: { $0.isNumber }) { return false }
        if !t.contains(where: { $0.isLetter }) { return false }
        let bad = ["отделение", "программ", "направлен", "дни недел", "иледен",
                   "сервиса", "питания", "красоты", "моды", "управления", "коммерции", "экономики"]
        let low = t.lowercased()
        for b in bad where low.contains(b) { return false }
        return true
    }

    // MARK: - Геометрия

    private static func median(_ xs: [Double]) -> Double {
        if xs.isEmpty { return 0 }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    private static func clusterRows(_ glyphs: [Glyph], tol: Double) -> [Row] {
        let gs = glyphs.sorted { $0.cy > $1.cy }
        var rows: [Row] = []
        for g in gs {
            if let li = rows.indices.last, abs(rows[li].cy - g.cy) <= tol {
                rows[li].g.append(g)
                let n = Double(rows[li].g.count)
                rows[li].cy += (g.cy - rows[li].cy) / n
            } else {
                rows.append(Row(cy: g.cy, g: [g]))
            }
        }
        return rows
    }

    private static func nearestColumn(_ xs: [Double], _ x: Double) -> Int {
        var best = 0
        var bestD = Double.greatestFiniteMagnitude
        for (i, v) in xs.enumerated() {
            let d = abs(v - x)
            if d < bestD {
                bestD = d
                best = i
            }
        }
        return best
    }

    private static func findWeekRow(_ rows: [Row]) -> (Int, [Double])? {
        for (ri, r) in rows.enumerated() {
            let gl = r.g.sorted { $0.cx < $1.cx }
            var words: [[Glyph]] = []
            var cur: [Glyph] = []
            for g in gl {
                if let last = cur.last, (g.cx - g.w / 2) - (last.cx + last.w / 2) > max(0.8 * g.w, 1.0) {
                    words.append(cur)
                    cur = []
                }
                cur.append(g)
            }
            if !cur.isEmpty { words.append(cur) }

            var nums: [(Int, Double)?] = []
            for w in words {
                let t = String(w.map { $0.ch })
                if let v = Int(t), t.allSatisfy({ $0.isNumber }) {
                    nums.append((v, w.reduce(0) { $0 + $1.cx } / Double(w.count)))
                } else {
                    nums.append(nil)
                }
            }
            for (i, n) in nums.enumerated() {
                guard let first = n, first.0 == 1 else { continue }
                var seq: [Double] = [first.1]
                var ok = true
                for k in 1..<52 {
                    let j = i + k
                    if j >= nums.count { ok = false; break }
                    guard let item = nums[j], item.0 == k + 1 else { ok = false; break }
                    seq.append(item.1)
                }
                if ok { return (ri, seq) }
            }
        }
        return nil
    }

    // MARK: - Одна страница

    static func parsePage(_ glyphs: [Glyph]) -> PageParse {
        let medH = median(glyphs.map { $0.h })
        let medW = median(glyphs.map { $0.w })
        let tol = 0.55 * medH
        let rows = clusterRows(glyphs, tol: tol)
        guard let found = findWeekRow(rows) else {
            return PageParse(events: [], hasWeekRow: false, groups: 0)
        }
        let wi = found.0
        let xs = found.1

        var diffs: [Double] = []
        for i in 0..<(xs.count - 1) { diffs.append(xs[i + 1] - xs[i]) }
        let pitch = median(diffs)
        if pitch <= 0 { return PageParse(events: [], hasWeekRow: true, groups: 0) }
        let left = xs[0] - pitch / 2
        let right = xs[xs.count - 1] + pitch / 2
        let weekY = rows[wi].cy

        let below = glyphs.filter { $0.cy < weekY - tol }
        let area = below.filter { $0.cx >= left && $0.cx <= right }
        let lefty = below.filter { $0.cx < left }

        // Строки недельной области
        var arows = clusterRows(area, tol: tol)
        var rowPitch = 0.0
        func recomputePitch() {
            var gaps: [Double] = []
            if arows.count > 1 {
                for i in 0..<(arows.count - 1) { gaps.append(arows[i].cy - arows[i + 1].cy) }
            }
            rowPitch = median(gaps)
        }
        recomputePitch()

        // Двухэтажные ячейки (код в две строки) склеиваем в одну строку
        if rowPitch > 0 {
            var merged: [Row] = []
            for r in arows {
                if let li = merged.indices.last, merged[li].cy - r.cy < 0.5 * rowPitch {
                    merged[li].g.append(contentsOf: r.g)
                    merged[li].cy = merged[li].g.reduce(0) { $0 + $1.cy } / Double(merged[li].g.count)
                } else {
                    merged.append(Row(cy: r.cy, g: r.g))
                }
            }
            arows = merged
            recomputePitch()
        }

        func isDateRow(_ r: Row) -> Bool {
            var dots = 0
            var letters = 0
            for g in r.g {
                if g.ch == "." || g.ch == "/" { dots += 1 }
                if g.ch.isLetter { letters += 1 }
            }
            return dots >= 8 && letters < 3
        }

        var skipped = 0
        while !arows.isEmpty && skipped < 3 && isDateRow(arows[0]) {
            arows.removeFirst()
            skipped += 1
        }
        if skipped == 0 {
            arows = Array(arows.dropFirst(2))  // как в боте: две строки с датами
        }

        func cells(_ r: Row) -> [Int: String] {
            let gl = r.g.sorted { $0.cx < $1.cx }
            var words: [[Glyph]] = []
            var cur: [Glyph] = []
            for g in gl {
                if let last = cur.last, (g.cx - g.w / 2) - (last.cx + last.w / 2) >= 0.25 * g.w {
                    words.append(cur)
                    cur = []
                }
                cur.append(g)
            }
            if !cur.isEmpty { words.append(cur) }

            var d: [Int: String] = [:]
            for w in words {
                guard let f = w.first, let l = w.last else { continue }
                let width = (l.cx + l.w / 2) - (f.cx - f.w / 2)
                if width <= 1.4 * pitch {
                    let cx = w.reduce(0) { $0 + $1.cx } / Double(w.count)
                    let ci = nearestColumn(xs, cx)
                    if abs(xs[ci] - cx) <= 0.6 * pitch {
                        d[ci, default: ""] += String(w.map { $0.ch })
                    }
                } else {
                    for g in w {
                        let ci = nearestColumn(xs, g.cx)
                        if abs(xs[ci] - g.cx) <= 0.6 * pitch {
                            d[ci, default: ""] += String(g.ch)
                        }
                    }
                }
            }
            return d
        }

        func isHeading(_ r: Row) -> Bool {
            let gl = r.g.sorted { $0.cx < $1.cx }
            let txt = String(gl.map { $0.ch }).lowercased()
            for k in badKeywords where txt.contains(k) { return true }
            if gl.contains(where: { $0.ch == "*" }) || gl.count >= 104 { return false }
            var run = 1
            var best = 1
            if gl.count > 1 {
                for i in 1..<gl.count {
                    let a = gl[i - 1]
                    let b = gl[i]
                    let tight = (b.cx - b.w / 2) - (a.cx + a.w / 2) < 0.25 * b.w
                    if tight && a.ch.isLetter && b.ch.isLetter {
                        run += 1
                    } else {
                        run = 1
                    }
                    best = max(best, run)
                }
            }
            return best >= 8
        }

        // Секции (заголовки разделов — границы) и «дырки» от пустых строк
        var sections: [[Row]] = [[]]
        var prevCy: Double? = nil
        for r in arows {
            if isHeading(r) {
                if !(sections[sections.count - 1].isEmpty) { sections.append([]) }
                prevCy = nil
                continue
            }
            if let p = prevCy, rowPitch > 0 {
                let k = Int(((p - r.cy) / rowPitch).rounded())
                if k > 1 {
                    for j in 0..<(k - 1) {
                        sections[sections.count - 1].append(Row(cy: p - rowPitch * Double(j + 1), g: [], synthetic: true))
                    }
                }
            }
            sections[sections.count - 1].append(r)
            prevCy = r.cy
        }

        // Имена групп слева
        let lrows = clusterRows(lefty, tol: tol)
        var names: [NameWord] = []
        for r in lrows {
            let gl = r.g.sorted { $0.cx < $1.cx }
            var cur: [Glyph] = []
            var words: [[Glyph]] = []
            for g in gl {
                if let last = cur.last, (g.cx - g.w / 2) - (last.cx + last.w / 2) > max(1.5 * medW, 2.0) {
                    words.append(cur)
                    cur = []
                }
                cur.append(g)
            }
            if !cur.isEmpty { words.append(cur) }
            for w in words {
                names.append(NameWord(t: String(w.map { $0.ch }),
                                      cx: w.reduce(0) { $0 + $1.cx } / Double(w.count),
                                      cy: r.cy, h: medH))
            }
        }
        names.sort { $0.cy > $1.cy }
        var joined: [NameWord] = []
        for n in names {
            var target: Int? = nil
            for (i, j) in joined.enumerated() {
                if (j.t.hasSuffix("-") || j.t.hasSuffix("–")) && j.cy - n.cy > 0 && j.cy - n.cy < 2.2 * n.h
                    && abs(j.cx - n.cx) < 25 {
                    target = i
                    break
                }
            }
            if let ti = target {
                joined[ti].t += n.t
                joined[ti].cy = (joined[ti].cy + n.cy) / 2
            } else {
                joined.append(n)
            }
        }
        let cand = joined.filter { isGroupCode($0.t) }

        // Блоки по 6 строк (Пн–Сб)
        var blocks: [(String, [Row])] = []
        for sec in sections {
            var k = 0
            while k < sec.count {
                let end = min(k + 6, sec.count)
                let chunk = Array(sec[k..<end])
                k += 6
                if chunk.count != 6 { continue }
                let top = chunk[0].cy + rowPitch / 2
                let bottom = chunk[5].cy - rowPitch / 2
                let inside = cand.filter { $0.cy >= bottom && $0.cy <= top }
                if inside.count != 1 { continue }
                blocks.append((inside[0].t, chunk))
            }
        }

        var events: [CalEvent] = []
        for (name, chunk) in blocks {
            for (wd, r) in chunk.enumerated() {
                if r.synthetic || r.g.isEmpty { continue }
                let rowText = String(r.g.map { $0.ch }).lowercased()
                var leaked = false
                for kw in badKeywords where rowText.contains(kw) { leaked = true }
                if leaked { continue }
                for (ci, text) in cells(r) {
                    if let c = classify(text) {
                        events.append(CalEvent(group: name, week: ci + 1, weekday: wd, kind: c.0, label: c.1))
                    }
                }
            }
        }
        return PageParse(events: events, hasWeekRow: true, groups: blocks.count)
    }

    // MARK: - События → периоды

    static func buildPeriods(_ events: [CalEvent], startYear: Int) -> [String: [CalPeriod]] {
        let cal = AppTime.calendar
        var comps = DateComponents()
        comps.year = startYear
        comps.month = 9
        comps.day = 1
        guard let sept1 = cal.date(from: comps) else { return [:] }
        let anchor = AppTime.monday(of: sept1)

        var byGroup: [String: [(Date, String, String)]] = [:]
        for e in events {
            let off = 7 * (e.week - 1) + e.weekday
            let d = AppTime.addDays(anchor, off)
            byGroup[e.group, default: []].append((d, e.kind, e.label))
        }

        var result: [String: [CalPeriod]] = [:]
        for (group, recsRaw) in byGroup {
            let recs = recsRaw.sorted { $0.0 < $1.0 }
            var out: [CalPeriod] = []
            var cur: CalPeriod? = nil
            var prev: Date? = nil
            for (d, kind, label) in recs {
                var continuous = false
                if let p = prev, let c = cur, c.kind == kind {
                    let days = cal.dateComponents([.day], from: p, to: d).day ?? 99
                    continuous = days <= 2
                }
                if continuous, var c = cur {
                    c.end = d
                    cur = c
                } else {
                    if let c = cur { out.append(c) }
                    cur = CalPeriod(kind: kind, label: label, start: d, end: d)
                }
                prev = d
            }
            if let c = cur { out.append(c) }
            result[group] = out
        }
        return result
    }
}
