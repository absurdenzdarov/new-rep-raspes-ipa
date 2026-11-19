import SwiftUI
import PDFKit

private enum PeriodStatus {
    case past, current, upcoming
}

private func startOfYear(_ y: Int) -> Date {
    var c = DateComponents()
    c.year = y
    c.month = 9
    c.day = 1
    return AppTime.calendar.date(from: c) ?? Date()
}

private func daysBetween(_ a: Date, _ b: Date) -> Int {
    return AppTime.calendar.dateComponents([.day], from: a, to: b).day ?? 0
}

private func status(_ p: CalPeriod, today: Date) -> PeriodStatus {
    if today > p.end { return .past }
    if today >= p.start { return .current }
    return .upcoming
}

private func normalizeGroup(_ s: String) -> String {
    return s.uppercased()
        .replacingOccurrences(of: "–", with: "-")
        .replacingOccurrences(of: "—", with: "-")
        .replacingOccurrences(of: " ", with: "")
}

struct CalendarView: View {
    @EnvironmentObject private var store: ScheduleStore
    @StateObject private var cal = CalendarStore()

    @State private var chosen: String?
    @State private var showPicker = false
    @State private var showPDF = false

    private func resolve(_ name: String, in d: CalendarData) -> String? {
        if d.groups[name] != nil { return name }
        let n = normalizeGroup(name)
        return d.groups.keys.first { normalizeGroup($0) == n }
    }

    private func currentGroup(_ d: CalendarData) -> String? {
        if let c = chosen, d.groups[c] != nil { return c }
        if let s = store.selected, s.kind == .group, let m = resolve(s.name, in: d) { return m }
        for f in store.favorites where f.kind == .group {
            if let m = resolve(f.name, in: d) { return m }
        }
        return d.groupNames.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                content
            }
            .navigationTitle("Учебный график")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showPDF = true
                        } label: {
                            Label("Открыть оригинал PDF", systemImage: "doc.richtext")
                        }
                        Button {
                            Task { await cal.load(pageURL: store.calendarPage, force: true) }
                        } label: {
                            Label("Обновить", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task { await cal.load(pageURL: store.calendarPage) }
            .sheet(isPresented: $showPDF) {
                PDFSheet(document: cal.document, group: cal.data.flatMap { currentGroup($0) })
                    .presentationBackground(.clear)
            }
            .sheet(isPresented: $showPicker) {
                GroupPickerSheet(groups: cal.data?.groupNames ?? []) { g in
                    showPicker = false
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { chosen = g }
                }
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch cal.state {
        case .idle, .loading:
            VStack(spacing: 18) {
                Spacer()
                OrbitLoader()
                    .frame(width: 190, height: 190)
                Text(cal.statusText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .failed(let msg):
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: "doc.badge.ellipsis")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Theme.gradient)
                Text("Не удалось загрузить график")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text(msg)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                Button("Повторить") {
                    Task { await cal.load(pageURL: store.calendarPage, force: true) }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .ready:
            if let d = cal.data, !d.groups.isEmpty, let g = currentGroup(d) {
                CalendarGroupView(data: d, group: g, showPicker: $showPicker, showPDF: $showPDF,
                                  onChoose: { name in
                                      withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { chosen = name }
                                  })
            } else {
                fallback
            }
        }
    }

    private var fallback: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Таблицу не удалось разобрать автоматически", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.orange)
                Text("Показываю исходный PDF. Если хотите, чтобы график выглядел как в боте, пришлите этот файл разработчику.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.65))
                if let note = cal.data?.diagnostics {
                    Text(note)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .textSelection(.enabled)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius: 22, tint: Color.orange.opacity(0.3))
            .padding(.horizontal, 14)

            PDFSheet(document: cal.document, group: nil, inline: true)
                .padding(.horizontal, 14)
                .padding(.bottom, 100)
        }
    }
}

// MARK: - Экран группы

struct CalendarGroupView: View {
    @EnvironmentObject private var store: ScheduleStore
    let data: CalendarData
    let group: String
    @Binding var showPicker: Bool
    @Binding var showPDF: Bool
    let onChoose: (String) -> Void

    @State private var showPast = false

    private var periods: [CalPeriod] {
        return (data.groups[group] ?? []).sorted { $0.start < $1.start }
    }

    private var favoriteGroups: [String] {
        var out: [String] = []
        for f in store.favorites where f.kind == .group {
            let n = normalizeGroup(f.name)
            if let m = data.groups.keys.first(where: { normalizeGroup($0) == n }), !out.contains(m) {
                out.append(m)
            }
        }
        return out
    }

    var body: some View {
        let today = AppTime.startOfDay(Date())
        let cur = periods.filter { status($0, today: today) == .current }
        let next = periods.filter { status($0, today: today) == .upcoming }
        let past = periods.filter { status($0, today: today) == .past }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                groupBar
                header
                HeroPeriod(current: cur.first, next: next.first, today: today)
                YearStrip(periods: periods, startYear: data.startYear, today: today)

                if !cur.isEmpty {
                    sectionTitle("Сейчас")
                    ForEach(Array(cur.enumerated()), id: \.element.id) { i, p in
                        PeriodCard(period: p, today: today, index: i)
                    }
                }
                if !next.isEmpty {
                    sectionTitle("Впереди")
                    ForEach(Array(next.enumerated()), id: \.element.id) { i, p in
                        PeriodCard(period: p, today: today, index: i + cur.count)
                    }
                }
                if !past.isEmpty {
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { showPast.toggle() }
                    } label: {
                        HStack {
                            Image(systemName: showPast ? "chevron.up" : "chevron.down")
                            Text(showPast ? "Скрыть прошедшие" : "Показать прошедшие (\(past.count))")
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .glass(Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                    if showPast {
                        ForEach(Array(past.enumerated()), id: \.element.id) { i, p in
                            PeriodCard(period: p, today: today, index: i)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }

                if periods.isEmpty {
                    Text("Для этой группы в графике нет особых периодов — только учёба.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glass(radius: 22)
                }

                legend

                Button {
                    Haptics.tap()
                    showPDF = true
                } label: {
                    Label("Открыть оригинал PDF", systemImage: "doc.richtext")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .glass(Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
    }

    private var groupBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        Haptics.tap()
                        showPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet")
                            Text("Все группы")
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 15)
                        .frame(height: 40)
                        .glass(Capsule(), tint: Theme.accent, interactive: true)
                    }
                    .buttonStyle(.plain)

                    ForEach(favoriteGroups, id: \.self) { g in
                        Button {
                            Haptics.select()
                            onChoose(g)
                        } label: {
                            Text(g)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(g == group ? 1 : 0.75))
                                .padding(.horizontal, 15)
                                .frame(height: 40)
                                .glass(Capsule(), tint: g == group ? Theme.cyan.opacity(0.7) : nil, interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, -20)
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("УЧЕБНЫЙ ГОД \(data.startYear)–\(data.startYear + 1)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.cyan)
            Text(group)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.titleGradient)
                .shadow(color: Theme.accent.opacity(0.6), radius: 10)
                .id(group)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity))
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: group)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.55))
            .textCase(.uppercase)
            .padding(.top, 6)
            .padding(.horizontal, 4)
    }

    private var legend: some View {
        let kinds = Array(Set(periods.map { $0.kind })).sorted()
        return Group {
            if !kinds.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Условные обозначения")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .textCase(.uppercase)
                    FlowLayout(spacing: 8) {
                        ForEach(kinds, id: \.self) { k in
                            let st = CalStyle.style(k)
                            HStack(spacing: 6) {
                                Circle().fill(st.color).frame(width: 8, height: 8)
                                Text(CalStyle.legend(k))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .glass(Capsule())
                        }
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - Переносящий раскладчик для легенды

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW && x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Главная карточка

struct HeroPeriod: View {
    let current: CalPeriod?
    let next: CalPeriod?
    let today: Date

    var body: some View {
        Group {
            if let c = current {
                card(period: c, caption: "СЕЙЧАС", isCurrent: true)
            } else if let n = next {
                card(period: n, caption: "ДАЛЬШЕ", isCurrent: false)
            } else {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.gradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Все периоды года завершены")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("Хорошего отдыха")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(16)
                .glass(radius: 28)
            }
        }
    }

    private func card(period p: CalPeriod, caption: String, isCurrent: Bool) -> some View {
        let st = CalStyle.style(p.kind)
        let total = max(daysBetween(p.start, p.end) + 1, 1)
        let elapsed = isCurrent ? daysBetween(p.start, today) + 1 : 0
        let untilStart = max(daysBetween(today, p.start), 0)
        let progress = isCurrent ? Double(elapsed) / Double(total) : 1 - Double(min(untilStart, 60)) / 60.0
        let leftDays = isCurrent ? max(daysBetween(today, p.end), 0) : max(daysBetween(today, p.start), 0)
        let center = isCurrent ? (leftDays == 0 ? "!" : "\(leftDays)") : "\(leftDays)"
        let unit = isCurrent ? (leftDays == 0 ? "последний" : "дн осталось") : "дн до начала"

        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(progress, 0.03), 1)))
                    .stroke(st.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: st.color.opacity(0.8), radius: 6)
                VStack(spacing: 0) {
                    Text(center)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(unit)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 6)
            }
            .frame(width: 88, height: 88)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: st.icon)
                    Text(caption)
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(st.color)
                Text(p.label)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(RU.rangeHuman(p.start, p.end))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glass(radius: 28, tint: st.color.opacity(isCurrent ? 0.5 : 0.3))
    }
}

// MARK: - Год одной полоской

struct YearStrip: View {
    let periods: [CalPeriod]
    let startYear: Int
    let today: Date

    @State private var reveal: CGFloat = 0

    private static let monthLetters = ["С", "О", "Н", "Д", "Я", "Ф", "М", "А", "М", "И", "И", "А"]

    var body: some View {
        let ys = startOfYear(startYear)
        let ye = startOfYear(startYear + 1)
        let total = max(Double(daysBetween(ys, ye)), 1)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Весь год")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .textCase(.uppercase)

            GeometryReader { geo in
                let W = geo.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: W, height: 24)

                    ZStack(alignment: .topLeading) {
                        ForEach(periods) { p in
                            let a = min(max(Double(daysBetween(ys, p.start)) / total, 0), 1)
                            let b = min(max(Double(daysBetween(ys, p.end) + 1) / total, 0), 1)
                            let st = CalStyle.style(p.kind)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(st.color)
                                .shadow(color: st.color.opacity(0.7), radius: 4)
                                .frame(width: max(4, W * CGFloat(b - a)), height: 24)
                                .offset(x: W * CGFloat(a))
                        }
                    }
                    .frame(width: W, height: 24, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .scaleEffect(x: reveal, anchor: .leading)

                    // Месяцы
                    ForEach(0..<12, id: \.self) { m in
                        let md = AppTime.calendar.date(byAdding: .month, value: m, to: ys) ?? ys
                        let f = Double(daysBetween(ys, md)) / total
                        Text(YearStrip.monthLetters[m])
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .offset(x: W * CGFloat(f) + 3, y: 30)
                    }

                    // Сегодня
                    let tf = Double(daysBetween(ys, today)) / total
                    if tf >= 0 && tf <= 1 {
                        Capsule()
                            .fill(Color.white)
                            .frame(width: 3, height: 36)
                            .shadow(color: Theme.cyan, radius: 6)
                            .offset(x: W * CGFloat(tf) - 1.5, y: -6)
                            .opacity(reveal)
                    }
                }
            }
            .frame(height: 50)
        }
        .padding(16)
        .glass(radius: 26)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) { reveal = 1 }
        }
    }
}

// MARK: - Карточка периода

struct PeriodCard: View {
    let period: CalPeriod
    let today: Date
    let index: Int

    @State private var appeared = false

    var body: some View {
        let st = CalStyle.style(period.kind)
        let s = status(period, today: today)
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        return HStack(spacing: 14) {
            Image(systemName: st.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 48, height: 48)
                .background(st.color.opacity(0.85), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .shadow(color: st.color.opacity(0.7), radius: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(period.label)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text(RU.rangeHuman(period.start, period.end))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.8))
                Text("\(RU.rangeNumeric(period.start, period.end)) · \(period.dayCount) \(RU.plural(period.dayCount, "день", "дня", "дней"))")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                statusChip(s)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glass(shape, tint: st.color.opacity(s == .current ? 0.5 : 0.25))
        .overlay {
            if s == .current {
                SpinningBorder(shape: shape, lineWidth: 2)
            }
        }
        .opacity(appeared ? (s == .past ? 0.55 : 1) : 0)
        .offset(y: appeared ? 0 : 24)
        .scaleEffect(appeared ? 1 : 0.96)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.82).delay(Double(min(index, 8)) * 0.07)) {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private func statusChip(_ s: PeriodStatus) -> some View {
        switch s {
        case .current:
            let left = max(daysBetween(today, period.end), 0)
            HStack(spacing: 5) {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text(left == 0 ? "Идёт · последний день" : "Идёт · осталось \(left) \(RU.plural(left, "день", "дня", "дней"))")
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(Color.green)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.16), in: Capsule())
        case .upcoming:
            let d = max(daysBetween(today, period.start), 0)
            Text(d == 0 ? "Начинается сегодня" : "Через \(d) \(RU.plural(d, "день", "дня", "дней"))")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.cyan)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Theme.cyan.opacity(0.16), in: Capsule())
        case .past:
            Text("Завершено")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: Capsule())
        }
    }
}

// MARK: - Выбор группы

struct GroupPickerSheet: View {
    let groups: [String]
    let onPick: (String) -> Void
    @State private var query = ""

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? groups : groups.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered, id: \.self) { g in
                            Button {
                                Haptics.tap()
                                onPick(g)
                            } label: {
                                HStack {
                                    Text(g)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Theme.cyan)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .glass(radius: 18, interactive: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Группа")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Найти группу")
        }
    }
}
