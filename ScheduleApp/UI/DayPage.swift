import SwiftUI

enum LessonState {
    case none, upcoming, current, past
}

struct DayPage: View {
    @EnvironmentObject private var store: ScheduleStore
    let entity: Entity
    let day: Date

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 20)) { ctx in
            content(now: ctx.date)
        }
    }

    private func content(now: Date) -> some View {
        let raw = store.entries(entity, on: day)
        let items = Presenter.items(for: raw, meal: store.meal(for: entity))
        let isToday = AppTime.isToday(day, now: now)
        let nowMin = AppTime.minutesFloat(now)

        return ScrollView {
            VStack(spacing: 12) {
                banner(items: items, isToday: isToday, nowMin: nowMin)

                if isToday && !items.isEmpty {
                    HeroCard(items: items, nowMin: nowMin)
                }

                if items.isEmpty {
                    if store.lessons.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in SkeletonCard() }
                    } else {
                        emptyState
                    }
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        let st = state(item: item, isToday: isToday, nowMin: nowMin)
                        LessonCard(item: item, index: idx, state: st.0, progress: st.1, kind: entity.kind)
                            .scrollTransition { content, phase in
                                content
                                    .opacity(phase.isIdentity ? 1 : 0.35)
                                    .scaleEffect(phase.isIdentity ? 1 : 0.94)
                                    .blur(radius: phase.isIdentity ? 0 : 2)
                            }
                    }
                }
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func state(item: LessonItem, isToday: Bool, nowMin: Double) -> (LessonState, Double) {
        guard isToday, let s = item.start, let e = item.end, e > s else { return (.none, 0) }
        let a = Double(s)
        let b = Double(e)
        if nowMin >= b { return (.past, 1) }
        if nowMin >= a { return (.current, (nowMin - a) / (b - a)) }
        return (.upcoming, 0)
    }

    private func banner(items: [LessonItem], isToday: Bool, nowMin: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(RU.longDay(day))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                if isToday {
                    Text("сегодня")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .glass(Capsule(), tint: Theme.accent)
                }
                Spacer()
            }
            if let sum = Presenter.summary(items: items) {
                Text(sum)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Theme.gradient)
                .symbolEffect(.pulse)
                .padding(.top, 50)
            Text("В этот день пар нет")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("Можно отдыхать")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Главная карточка «сейчас / дальше»

struct HeroCard: View {
    let items: [LessonItem]
    let nowMin: Double

    var body: some View {
        let live = Presenter.live(items: items, now: nowMin)
        return Group {
            if let cur = live.current {
                currentCard(cur, next: live.next)
            } else if let next = live.next {
                nextCard(next)
            } else if live.finished {
                doneCard
            }
        }
    }

    private func ring(progress: Double, center: String, caption: String) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0.02), 1)))
                .stroke(Theme.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.cyan.opacity(0.7), radius: 6)
                .animation(.smooth(duration: 0.8), value: progress)
            VStack(spacing: 0) {
                Text(center)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(caption)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .frame(width: 84, height: 84)
    }

    private func currentCard(_ cur: LessonItem, next: LessonItem?) -> some View {
        let s = Double(cur.start ?? 0)
        let e = Double(cur.end ?? 0)
        let left = max(Int((e - nowMin).rounded(.up)), 0)
        let progress = e > s ? (nowMin - s) / (e - s) : 0
        return HStack(spacing: 16) {
            ring(progress: progress, center: "\(left)", caption: "мин")
            VStack(alignment: .leading, spacing: 5) {
                LiveBadge()
                Text(heroTitle(cur))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .lineLimit(2)
                if !cur.room.isEmpty {
                    Text("Каб. \(cur.room)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.cyan)
                }
                if let n = next {
                    Text("Дальше · \(Presenter.clock(n.start ?? 0)) \(heroTitle(n))")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glass(radius: 28, tint: Theme.accent.opacity(0.55))
    }

    private func nextCard(_ next: LessonItem) -> some View {
        let start = Double(next.start ?? 0)
        let left = max(Int((start - nowMin).rounded(.up)), 1)
        let progress = max(0, min(1, 1 - Double(left) / 90.0))
        let center: String = left >= 60 ? "\(left / 60)ч" : "\(left)"
        let caption: String = left >= 60 ? "\(left % 60) мин" : "мин"
        return HStack(spacing: 16) {
            ring(progress: progress, center: center, caption: caption)
            VStack(alignment: .leading, spacing: 5) {
                Text("СЛЕДУЮЩАЯ · \(Presenter.clock(next.start ?? 0))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.cyan)
                Text(heroTitle(next))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .lineLimit(2)
                if !next.room.isEmpty {
                    Text("Каб. \(next.room)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glass(radius: 28)
    }

    private var doneCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.gradient)
            VStack(alignment: .leading, spacing: 2) {
                Text("Занятия на сегодня закончились")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Хорошего вечера")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(16)
        .glass(radius: 28)
    }

    private func heroTitle(_ item: LessonItem) -> String {
        if case .elective = item.kind { return "Элективный курс" }
        return item.subject
    }
}

// MARK: - Карточки пар

struct LessonCard: View {
    let item: LessonItem
    let index: Int
    let state: LessonState
    let progress: Double
    let kind: SearchKind

    @State private var appeared = false

    var body: some View {
        cardBody
            .opacity(appeared ? (state == .past ? 0.55 : 1) : 0)
            .offset(y: appeared ? 0 : 26)
            .scaleEffect(appeared ? 1 : 0.96)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.82).delay(Double(min(index, 8)) * 0.07)) {
                    appeared = true
                }
            }
    }

    @ViewBuilder
    private var cardBody: some View {
        switch item.kind {
        case .regular:
            regularCard
        case .elective(let options):
            electiveCard(options)
        case .status(let label):
            statusCard(label)
        case .meal:
            mealCard
        }
    }

    private var timeColumn: some View {
        let parts = TimeParsing.split(item.time)
        let colors = Theme.subjectColors(item.subject)
        return VStack(spacing: 5) {
            Text(parts?.0 ?? item.time)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
            Capsule()
                .fill(LinearGradient(colors: [colors.0, colors.1], startPoint: .top, endPoint: .bottom))
                .frame(width: 3, height: 26)
                .shadow(color: colors.0.opacity(0.9), radius: 5)
            if let end = parts?.1 {
                Text(end)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
        .frame(width: 50)
    }

    private var groupsLine: String? {
        if item.groups.isEmpty { return nil }
        let joined = item.groups.joined(separator: ", ")
        return kind == .group ? "Вместе с: \(joined)" : "Группы: \(joined)"
    }

    private var regularCard: some View {
        let colors = Theme.subjectColors(item.subject)
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return HStack(alignment: .top, spacing: 12) {
            timeColumn
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if !item.numLabel.isEmpty {
                        Text(item.numLabel)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .textCase(.uppercase)
                    }
                    Spacer()
                    if state == .current { LiveBadge() }
                }
                Text(item.subject)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                if kind != .teacher && !item.teacher.isEmpty {
                    Label(item.teacher, systemImage: "person.fill")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
                if kind != .room && !item.room.isEmpty && item.room != "." {
                    RoomChip(room: item.room, subject: item.subject)
                }
                if let g = groupsLine {
                    Label(g, systemImage: "person.3.fill")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.cyan.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if state == .current {
                    ProgressTrack(progress: progress)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .glass(shape, tint: colors.0.opacity(state == .current ? 0.55 : 0.28))
        .overlay {
            if state == .current {
                SpinningBorder(shape: shape, lineWidth: 2)
            }
        }
        .shadow(color: state == .current ? Theme.accent.opacity(0.5) : Color.clear, radius: 18, y: 6)
    }

    private func electiveCard(_ options: [ElectiveOption]) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return HStack(alignment: .top, spacing: 12) {
            timeColumn
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Элективный курс — на выбор")
                    Spacer()
                    if state == .current { LiveBadge() }
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.cyan)

                if !item.numLabel.isEmpty {
                    Text(item.numLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .textCase(.uppercase)
                }
                ForEach(options, id: \.self) { opt in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(opt.subject)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                        if kind != .teacher && !opt.teacher.isEmpty {
                            Label(opt.teacher, systemImage: "person.fill")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.65))
                        }
                        if kind != .room && !opt.room.isEmpty {
                            RoomChip(room: opt.room, subject: opt.subject)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                if state == .current {
                    ProgressTrack(progress: progress)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .glass(shape, tint: Theme.violet.opacity(0.35))
        .overlay {
            if state == .current {
                SpinningBorder(shape: shape, lineWidth: 2)
            }
        }
    }

    private func statusCard(_ label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 26, weight: .semibold))
            Text(label)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .foregroundStyle(Color.white)
        .padding(18)
        .glass(radius: 26, tint: Theme.accent.opacity(0.7))
    }

    private var mealCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "fork.knife")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text("Обед")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            Text(item.time)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.65))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .glass(Capsule(), tint: Color.orange.opacity(0.35))
    }
}

struct RoomChip: View {
    let room: String
    let subject: String

    var body: some View {
        let c = Theme.subjectColors(subject).1
        return HStack(spacing: 5) {
            Image(systemName: "door.left.hand.open")
                .font(.system(size: 12, weight: .semibold))
            Text("Каб. \(room)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(c)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(c.opacity(0.16), in: Capsule())
    }
}

struct LiveBadge: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .scaleEffect(pulse ? 1.5 : 1)
                .opacity(pulse ? 0.5 : 1)
            Text("Идёт сейчас")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.16), in: Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct ProgressTrack: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(Theme.gradient)
                    .frame(width: max(8, geo.size.width * CGFloat(min(max(progress, 0), 1))))
                    .shadow(color: Theme.cyan.opacity(0.6), radius: 4)
            }
        }
        .frame(height: 6)
        .animation(.easeInOut(duration: 0.6), value: progress)
    }
}
