import SwiftUI

enum AppTab: Hashable {
    case schedule, calendar, settings, search
}

struct RootView: View {
    @EnvironmentObject private var store: ScheduleStore
    @State private var tab: AppTab = .schedule

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                Tab("Расписание", systemImage: "calendar", value: AppTab.schedule) {
                    ScheduleView(goToSearch: { tab = .search })
                }
                Tab("График", systemImage: "tablecells", value: AppTab.calendar) {
                    CalendarView()
                }
                Tab("Ещё", systemImage: "slider.horizontal.3", value: AppTab.settings) {
                    SettingsView()
                }
                Tab("Поиск", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                    SearchView(onOpen: { tab = .schedule })
                }
            }
            .tabBarGlassBehavior()
            .tint(Theme.cyan)

            if store.gate != .hidden {
                LoadingGate()
                    .zIndex(10)
                    .transition(.opacity.combined(with: .scale(scale: 1.06)))
            }
        }
        .animation(.smooth(duration: 0.55), value: store.gate)
    }
}
