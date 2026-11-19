import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: ScheduleStore
    @State private var linkText: String = ""
    @State private var calendarText: String = ""
    @State private var confirmClear = false

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Ещё")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.titleGradient)
                        .padding(.top, 10)

                    statusCard
                    sourceCard
                    dangerCard

                    Text("Расписание разбирается прямо на устройстве из Excel-файлов на Яндекс.Диске — без серверов и аккаунтов.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.horizontal, 6)
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            linkText = store.publicLink
            calendarText = store.calendarPage
        }
        .confirmationDialog("Очистить локальные данные расписания?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Очистить", role: .destructive) {
                store.clearCache()
                Task { await store.refresh(force: true) }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var statusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Данные", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                infoRow("Групп", "\(store.list(.group).count)")
                infoRow("Преподавателей", "\(store.list(.teacher).count)")
                infoRow("Кабинетов", "\(store.list(.room).count)")
                infoRow("Занятий", "\(store.lessons.count)")
                infoRow("Обновлено", format(store.lastUpdated))
                infoRow("Проверено", format(store.lastChecked))
                if let err = store.errorMessage {
                    Text(err)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.orange)
                }
                Button {
                    Haptics.tap()
                    Task { await store.refresh(force: true) }
                } label: {
                    Text("Обновить сейчас")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassPrimaryButtonStyle())
            }
            .padding(16)
        }
    }

    private var sourceCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Источники", systemImage: "link")
                    .font(.system(size: 16, weight: .bold, design: .rounded))

                fieldTitle("Папка расписания на Яндекс.Диске")
                field("https://disk.360.yandex.ru/d/…", text: $linkText)

                fieldTitle("Страница сайта с учебным графиком")
                field("https://…", text: $calendarText)

                HStack(spacing: 10) {
                    Button("Сохранить") {
                        Haptics.success()
                        store.calendarPage = calendarText.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await store.setLink(linkText) }
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    Button("Сбросить") {
                        linkText = ScheduleStore.defaultLink
                        calendarText = ScheduleStore.defaultCalendarPage
                        store.calendarPage = ScheduleStore.defaultCalendarPage
                        Task { await store.setLink(ScheduleStore.defaultLink) }
                    }
                    .buttonStyle(GlassSecondaryButtonStyle())
                }
            }
            .padding(16)
        }
    }

    private var dangerCard: some View {
        Button(role: .destructive) {
            confirmClear = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Очистить кэш")
                Spacer()
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.red.opacity(0.9))
            .padding(16)
            .glass(radius: 24, tint: Color.red.opacity(0.25), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func fieldTitle(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.55))
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .padding(12)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
    }

    private func format(_ d: Date?) -> String {
        guard let d = d else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = AppTime.zone
        f.dateFormat = "d MMM, HH:mm"
        return f.string(from: d)
    }
}
