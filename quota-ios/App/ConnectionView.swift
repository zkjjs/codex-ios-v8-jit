import SwiftUI

struct ConnectionView: View {
    @ObservedObject var model: QuotaModel
    @Environment(\.dismiss) private var dismiss
    @State private var server = ServerConnection.defaultServer
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("HTTPS 服务器地址", text: $server)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("只读查询码", text: $code)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("配对服务器") } footer: {
                    Text("使用服务器部署时生成的查询码。无需在手机上登录 OpenAI。")
                }
                Section {
                    Button {
                        Task { if await model.connect(server: server, code: code) { dismiss() } }
                    } label: {
                        HStack {
                            Text(model.loading ? "正在验证连接…" : "连接并读取额度")
                            Spacer()
                            if model.loading { ProgressView() }
                            else { Image(systemName: "arrow.up.right") }
                        }
                    }.disabled(model.loading || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
                }
                Section("桌面小组件") {
                    Label("黑色 / 白色 · 小号 / 中号", systemImage: "square.grid.2x2")
                    Text(SharedStore.groupAvailable
                         ? "当前签名支持共享配置。在 App 连接一次后，编辑小组件 → 配置来源 → 使用 App 内已保存的连接，无需重复输入。"
                         : "当前签名未提供 App Groups。iOS 17 及以上可编辑小组件 → 配置来源 → 手动输入服务器和查询码；iOS 16 需要支持 App Groups 的签名。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("液态玻璃在 iOS 26 启用；桌面玻璃效果跟随系统的透明/着色模式。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.connection != nil {
                    Section {
                        Button("断开服务器", role: .destructive) { model.disconnect(); code = ""; dismiss() }
                    } footer: {
                        Text("此操作清除 App 及共享小组件配置。手动配置过的小组件还需单独移除或清空查询码。")
                    }
                }
            }.navigationTitle("服务器").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.onAppear {
            if let connection = model.connection { server = connection.server; code = connection.accessCode }
        }
    }
}
