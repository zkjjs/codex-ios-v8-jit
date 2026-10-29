import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            LedgerHomeView()
                .tabItem { Label("账本", systemImage: "book.closed") }
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar") }
        }
        .tint(Theme.expense)
        .overlay { readingOverlay }
        .sheet(item: $model.editor, onDismiss: { model.editorDismissed() }) { draft in
            TransactionEditorView(draft: draft)
                .environmentObject(model)
        }
        .alert("无法完成", isPresented: alertPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onAppear { model.consumePendingImports() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.consumePendingImports()
            }
        }
        .onOpenURL { _ in
            model.consumePendingImports()
        }
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { isPresented in
                if !isPresented { model.alertMessage = nil }
            }
        )
    }

    @ViewBuilder
    private var readingOverlay: some View {
        if model.isReading {
            ZStack {
                Color.black.opacity(0.18).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在识别截图")
                        .font(.headline)
                }
                .padding(24)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}
