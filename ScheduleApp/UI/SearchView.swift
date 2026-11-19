import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var store: ScheduleStore
    let onOpen: () -> Void

    @State private var kind: SearchKind = .group
    @State private var query = ""
    @State private var showFreeRooms = false
    @Namespace private var ns

    private var all: [String] { store.list(kind) }

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    private func sectionKey(_ name: String) -> String {
        switch kind {
        case .group:
            return name.split(separator: "-").first.map { String($0) } ?? name
        case .teacher:
            return name.first.map { String($0).uppercased() } ?? "#"
        case .room:
            if let c = ScheduleStore.corpus(of: name) { return "Корпус \(c)" }
            return "Без корпуса"
        }
    }

    private var sections: [(String, [String])] {
        var dict: [String: [String]] = [:]
        var order: [String] = []
        for n in filtered {
            let k = sectionKey(n)
            if dict[k] == nil { order.append(k) }
            dict[k, default: []].append(n)
        }
        if kind == .room {
            order.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        return order.map { ($0, dict[$0] ?? []) }
    }

    private var favoritesOfKind: [Entity] {
        return store.favorites.filter { $0.kind == kind }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 0) {
                    kindPicker
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 10)

                    if all.isEmpty {
                        emptyOrLoading
                    } else {
                        list
                    }
                }
            }
            .navigationTitle("Поиск")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "Найти: \(kind.title.lowercased())")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .sheet(isPresented: $showFreeRooms) {
                FreeRoomsView(onOpen: { name in
                    showFreeRooms = false
                    store.select(Entity(kind: .room, name: name))
                    onOpen()
                })
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
            }
        }
    }

    // MARK: Переключатель вида

    private var kindPicker: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(SearchKind.allCases, id: \.self) { k in
                    let active = kind == k
                    Button {
                        Haptics.select()
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            kind = k
                            query = ""
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: k.icon)
                                .font(.system(size: 16, weight: .semibold))
                            Text(k.title)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(Color.white.opacity(active ? 1 : 0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Theme.gradient)
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                                    .shadow(color: Theme.accent.opacity(0.55), radius: 10, y: 3)
                                    .matchedGeometryEffect(id: "kindSelection", in: ns)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .glass(radius: 24)
        }
    }

    // MARK: Список

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if kind == .room && query.isEmpty {
                    freeRoomsCard
                }

                if query.isEmpty && !favoritesOfKind.isEmpty {
                    sectionTitle("Избранное", icon: "star.fill")
                    ForEach(favoritesOfKind) { e in
                        EntityRow(entity: e, onOpen: onOpen)
                    }
                }

                ForEach(sections, id: \.0) { section in
                    sectionTitle(section.0, icon: nil)
                    ForEach(section.1, id: \.self) { name in
                        EntityRow(entity: Entity(kind: kind, name: name), onOpen: onOpen)
                    }
                }

                if filtered.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 34))
                            .foregroundStyle(Theme.gradient)
                        Text("Ничего не найдено")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 50)
                }
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var freeRoomsCard: some View {
        Button {
            Haptics.tap()
            showFreeRooms = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
                    .frame(width: 46, height: 46)
                    .glass(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Свободные кабинеты")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Какие аудитории свободны прямо сейчас")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(14)
            .glass(radius: 26, tint: Theme.accent.opacity(0.35), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ text: String, icon: String?) -> some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon).foregroundStyle(Color.yellow)
            }
            Text(text)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .textCase(.uppercase)
        }
        .padding(.top, 10)
        .padding(.horizontal, 4)
    }

    private var emptyOrLoading: some View {
        VStack(spacing: 14) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Theme.gradient)
                .padding(.top, 60)
            Text("Данных пока нет")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.7))
            Button("Обновить") {
                Task { await store.refresh(force: true) }
            }
            .buttonStyle(GlassPrimaryButtonStyle())
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Строка списка

struct EntityRow: View {
    @EnvironmentObject private var store: ScheduleStore
    let entity: Entity
    let onOpen: () -> Void

    @State private var starBounce = 0

    private var badge: String {
        switch entity.kind {
        case .group:
            return entity.name.split(separator: "-").first.map { String($0) } ?? entity.name
        case .teacher:
            return entity.name.first.map { String($0).uppercased() } ?? "?"
        case .room:
            return entity.name.split(separator: "/").first.map { String($0) } ?? entity.name
        }
    }

    var body: some View {
        let fav = store.isFavorite(entity)
        return HStack(spacing: 12) {
            Button {
                Haptics.tap()
                store.select(entity)
                onOpen()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Theme.gradient)
                        Text(badge)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .minimumScaleFactor(0.55)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                    }
                    .frame(width: 44, height: 44)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entity.name)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .lineLimit(2)
                        Text("\(store.lessonsCount(entity)) занятий в базе")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Haptics.success()
                starBounce += 1
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    store.toggleFavorite(entity)
                }
            } label: {
                Image(systemName: fav ? "star.fill" : "star")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(fav ? Color.yellow : Color.white.opacity(0.55))
                    .symbolEffect(.bounce, value: starBounce)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glass(radius: 24, tint: fav ? Color.yellow.opacity(0.35) : nil)
    }
}

// MARK: - Свободные кабинеты

struct FreeRoomsView: View {
    @EnvironmentObject private var store: ScheduleStore
    let onOpen: (String) -> Void

    @State private var corpus: String = ""

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { ctx in
            content(now: ctx.date)
        }
        .onAppear {
            if corpus.isEmpty { corpus = store.corpuses.first ?? "" }
        }
    }

    private func content(now: Date) -> some View {
        let result = store.freeRooms(corpus: corpus, now: now)
        return ZStack {
            AppBackground()
            VStack(alignment: .leading, spacing: 14) {
                Text("Свободные кабинеты")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.titleGradient)
                Text("Сейчас \(Presenter.clock(Int(AppTime.minutesFloat(now))))")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))

                if store.corpuses.isEmpty {
                    note("В названиях кабинетов нет номера корпуса (например, 208/3), поэтому подбор по корпусам недоступен.")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        GlassGroup(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(store.corpuses, id: \.self) { c in
                                    Button {
                                        Haptics.select()
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { corpus = c }
                                    } label: {
                                        Text("Корпус \(c)")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(Color.white)
                                            .padding(.horizontal, 16)
                                            .frame(height: 38)
                                            .glass(Capsule(), tint: corpus == c ? Theme.accent : nil, interactive: true)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if !result.hasData {
                        note("На сегодня в базе нет расписания — выходной, каникулы или данных ещё нет.")
                    } else if result.rooms.isEmpty {
                        note("Сейчас в этом корпусе свободных кабинетов нет.")
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 10)], spacing: 10) {
                                ForEach(result.rooms, id: \.self) { r in
                                    Button {
                                        Haptics.tap()
                                        onOpen(r)
                                    } label: {
                                        Text(r.split(separator: "/").first.map { String($0) } ?? r)
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                            .foregroundStyle(Color.white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 46)
                                            .glass(radius: 16, tint: Color.green.opacity(0.4), interactive: true)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 30)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.65))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(radius: 20)
    }
}
