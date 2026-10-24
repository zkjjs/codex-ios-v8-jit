import SwiftUI

struct SettingsView: View {
    let store: QuotaStore
    @State private var confirmLogout = false
    @State private var showEmail = false
    var body: some View {
        NavigationStack {
            Form {
                Section("账号") {
                    LabeledContent("登录状态", value: store.isSignedIn ? "已连接 ChatGPT" : "未登录")
                    if store.isSignedIn {
                        LabeledContent("套餐", value: (store.snapshot?.plan ?? "未知").uppercased())
                        Toggle("显示账号邮箱", isOn: $showEmail)
                        if showEmail, let email = store.credentials?.email { Text(email).textSelection(.enabled) }
                        Button("退出登录", role: .destructive) { confirmLogout = true }
                    }
                }
                Section {
                    Toggle("隐藏小组件中的额度", isOn: Binding(get: { store.privacyHidden }, set: { store.setPrivacy($0) }))
                    Label("小号：剩余额度与重置时间", systemImage: "square")
                    Label("中号：两个额度周期与重置时间", systemImage: "rectangle")
                    Text("长按桌面空白处 → 编辑 → 添加小组件 → 搜索「Codex 额度」。")
                    Text("倒计时由系统显示；网络刷新由 iOS 安排。重置时间到达后，需成功查询才能确认最新额度。")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("桌面小组件") }
                Section("连接与安装") {
                    Text("如设备码登录不可用，请到 ChatGPT 的安全设置中开启设备码授权，再重新生成登录码。")
                    Text("小组件需签名工具保留 Widget 扩展、App Groups 与共享钥匙串权限。若安装时被移除，小组件可能无法添加或同步。")
                    if let warning = store.sharingWarning { Text(warning).foregroundStyle(.orange) }
                    Link("打开 Codex 官方额度页面", destination: URL(string: "https://chatgpt.com/codex/settings/usage")!)
                }
                Section("隐私") {
                    Text("凭证存储在此设备的系统钥匙串。刷新令牌仅由主应用读取，所有账号请求直接发往 OpenAI。无广告、无分析上报。")
                    Text("本工具只查询使用情况，不发送生成请求。")
                }
                Section { LabeledContent("版本", value: "1.0.0") }
            }
            .navigationTitle("设置")
            .confirmationDialog("退出此账号？", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) { store.logout() }
                Button("取消", role: .cancel) { }
            } message: { Text("将清除本机账号凭证和小组件的额度数据。") }
        }
    }
}
