import SwiftUI

struct ServerPairingView: View {
    let store: QuotaStore
    @State private var text = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section {
                Text("先在日本服务器运行安装脚本，再把终端输出的配对 JSON 粘贴到这里。")
                Text("配对包含服务器地址、访问密钥和证书指纹。App 会验证服务器身份，OpenAI 令牌保留在服务器。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("连接你的服务器") }
            Section {
                PasteButton(payloadType: String.self) { values in text = values.first ?? "" }
                TextEditor(text: $text).font(.system(.caption,design:.monospaced)).frame(minHeight:180)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Text("配对 JSON") }
            if let error { Section { Text(error).foregroundStyle(.orange) } }
            Section {
                Button("保存并连接") {
                    do {
                        try store.pair(text.trimmingCharacters(in:.whitespacesAndNewlines))
                        Task { await store.refresh() }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.disabled(text.isEmpty)
            }
            Section {
                Text("默认 HTTPS 端口为 8765，AWS 安全组需允许手机访问。小组件仍需签名保留扩展和共享权限。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("连接服务器").navigationBarTitleDisplayMode(.inline)
    }
}
