import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: ScheduleStore
    let goToSearch: () -> Void

    @State private var selectedDate: Date = ScheduleView.initialDate()
    @State private var starBounce = 0
    @Namespace private var ns

    static func initialDate() -> Date {
        var d = AppTime.startOfDay(Date())
        if AppTime.weekdayIndex(d) == 6 { d = AppTime.addDays(d, 1) }
        return d
    }

    private var currentMonday: Date { AppTime.monday(of: selectedDate) }

    private var weekDays: [Date] {
        return (0..<6).map { AppTime.addDays(currentMonday, $0) }
    }

    private var minMonday: Date {
        let cur = AppTime.monday(of: ScheduleView.initialDate())
        return min(store.weekStarts.first ?? cur, cur)
    }

    private var maxMonday: Date {
        let cur = AppTime.monday(of: ScheduleView.initialDate())
        return max(store.weekStarts.last ?? cur, cur)
    }

    private var chipEntities: [Entity] {
        var list = store.favorites
        if let e = store.selected, !list.contains(e) { list.append(e) }
        return list
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                if let entity = store.selected {
                    header(entity)
                    if let err = store.errorMessage, store.gate == .hidden {
                        errorBanner(err)
                    }
                    chips
                    if entity.kind == .teacher {
                        subjectsRow(entity)
                    }
                    weekBar
                    dayStrip(entity)
                    pages(entity)
                } else {
                    onboarding
                }
            }
        }
    }

    // MARK: Шапка

    private func header(_ entity: Entity) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: entity.kind.icon)
                    Text(entity.kind.single)
                        .textCase(.uppercase)
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.cyan)

                Text(entity.name)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.titleGradient)
                    .shadow(color: Theme.accent.opacity(0.6), radius: 10)
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
                    .id(entity.id)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity))

                Text(updatedCaption)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            Spacer(minLength: 4)

            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    let fav = store.isFavorite(entity)
                    GlassIconButton(systemName: fav ? "star.fill" : "star", tint: fav ? Color.yellow.opacity(0.55) : nil) {
                        starBounce += 1
                        Haptics.success()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            store.toggleFavorite(entity)
                        }
                    }
                    .symbolEffect(.bounce, value: starBounce)

                    GlassIconButton(systemName: "arrow.clockwise") {
                        Task { await store.refresh(force: true) }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: entity.id)
    }

    private var updatedCaption: String {
        if let u = store.lastChecked ?? store.lastUpdated {
            let mins = Int(Date().timeIntervalSince(u) / 60)
            if mins < 1 { return "Данные обновлены только что" }
            if mins < 60 { return "Данные обновлены \(mins) мин назад" }
            if mins < 1440 { return "Данные обновлены \(mins / 60) ч назад" }
            return "Данные обновлены \(mins / 1440) дн назад"
        }
        return "Расписание"
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(Color.orange)
            Text("Показаны сохранённые данные")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Обновить") {
                Task { await store.refresh(force: true) }
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .tint(Theme.cyan)
        }
        .padding(12)
        .glass(radius: 18, tint: Color.orange.opacity(0.4))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Избранное

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(chipEntities) { e in
                        chip(e)
                    }
                    GlassIconButton(systemName: "plus", size: 40) {
                        goToSearch()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
        .padding(.bottom, 8)
    }

    private func chip(_ e: Entity) -> some View {
        let active = store.selected == e
        return Button {
            Haptics.select()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                store.select(e)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: e.kind.icon)
                    .font(.system(size: 12, weight: .bold))
                Text(e.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white.opacity(active ? 1 : 0.75))
            .padding(.horizontal, 15)
            .frame(height: 40)
            .glass(Capsule(), tint: active ? Theme.accent : nil, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func subjectsRow(_ e: Entity) -> some View {
        let subs = store.subjects(forTeacher: e.name)
        return Group {
            if !subs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Image(systemName: "books.vertical.fill")
                            .foregroundStyle(Theme.cyan)
                        ForEach(subs, id: \.self) { s in
                            Text(s)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .glass(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
                .padding(.bottom, 6)
            }
        }
    }

    // MARK: Неделя и дни

    private var weekBar: some View {
        HStack {
            GlassIconButton(systemName: "chevron.left", size: 38) { shiftWeek(-1) }
                .opacity(currentMonday > minMonday ? 1 : 0.3)
                .disabled(!(currentMonday > minMonday))
            Spacer()
            VStack(spacing: 2) {
                Text(RU.weekRange(monday: currentMonday))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                if currentMonday == AppTime.monday(of: ScheduleView.initialDate()) {
                    Text("текущая неделя")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.5))
                } else {
                    Button("Вернуться к сегодня") {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            selectedDate = ScheduleView.initialDate()
                        }
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tint(Theme.cyan)
                }
            }
            .animation(.smooth(duration: 0.3), value: currentMonday)
            Spacer()
            GlassIconButton(systemName: "chevron.right", size: 38) { shiftWeek(1) }
                .opacity(currentMonday < maxMonday ? 1 : 0.3)
                .disabled(!(currentMonday < maxMonday))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func shiftWeek(_ dir: Int) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            selectedDate = AppTime.addDays(selectedDate, 7 * dir)
        }
    }

    private func dayStrip(_ entity: Entity) -> some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { day in
                    dayCell(day, entity: entity)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func dayCell(_ day: Date, entity: Entity) -> some View {
        let selected = day == selectedDate
        let today = AppTime.isToday(day, now: Date())
        let has = store.hasLessons(entity, on: day)
        return Button {
            Haptics.select()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                selectedDate = day
            }
        } label: {
            VStack(spacing: 5) {
                Text(RU.weekdayShort[AppTime.weekdayIndex(day)])
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(selected ? 0.9 : 0.55))
                Text("\(AppTime.dayNumber(day))")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(today && !selected ? Theme.cyan : Color.white)
                Circle()
                    .fill(selected ? Color.white : Theme.cyan)
                    .frame(width: 5, height: 5)
                    .opacity(has ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.gradient)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                        .shadow(color: Theme.accent.opacity(0.6), radius: 12, y: 4)
                        .matchedGeometryEffect(id: "daySelection", in: ns)
                }
            }
            .glass(RoundedRectangle(cornerRadius: 20, style: .continuous),
                   tint: nil, interactive: true)
            .overlay {
                if today && !selected {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.cyan.opacity(0.8), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func pages(_ entity: Entity) -> some View {
        TabView(selection: $selectedDate) {
            ForEach(weekDays, id: \.self) { day in
                DayPage(entity: entity, day: day)
                    .tag(day)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxHeight: .infinity)
    }

    // MARK: Пустое состояние

    private var onboarding: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().fill(Theme.gradient).frame(width: 120, height: 120).opacity(0.22).blur(radius: 14)
                Image(systemName: "sparkles")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(Theme.gradient)
                    .symbolEffect(.pulse)
            }
            Text("Выберите, что смотреть")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.titleGradient)
            Text("Группа, преподаватель или кабинет — добавьте в избранное, и расписание всегда будет под рукой.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Открыть поиск") {
                Haptics.tap()
                goToSearch()
            }
            .buttonStyle(GlassPrimaryButtonStyle())
            Spacer()
            Spacer()
        }
    }
}
