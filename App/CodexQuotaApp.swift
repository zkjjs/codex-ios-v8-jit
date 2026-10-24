import SwiftUI

@main
struct CodexQuotaApp: App {
    @State private var store = QuotaStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .tint(Color.quotaMint)
                .task { await store.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.refresh() } }
                }
                .onOpenURL { _ in Task { await store.refresh() } }
        }
    }
}

struct RootView: View {
    let store: QuotaStore
    var body: some View {
        TabView {
            Tab("额度", systemImage: "chart.pie.fill") {
                DashboardView(store: store)
            }
            Tab("设置", systemImage: "slider.horizontal.3") {
                SettingsView(store: store)
            }
        }
    }
}
