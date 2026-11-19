import SwiftUI

@main
struct ScheduleApp: App {
    @StateObject private var store = ScheduleStore()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task { await store.refresh() }
                .onChange(of: phase) { _, newPhase in
                    if newPhase == .active {
                        Task { await store.refresh() }
                    }
                }
        }
    }
}
