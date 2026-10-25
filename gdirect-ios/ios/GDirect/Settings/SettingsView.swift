import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var loginError: String?
    @State private var showLoginHelp = false
    @State private var importing = false

    var body: some View {
        Form {
            Section("Google Drive") {
                if let email = model.auth.email {
                    Text(email)
                    Button("退出登录", role: .destructive) {
                        if let account = model.auth.accountID { model.coordinator?.pauseAccount(account) }
                        model.auth.signOut()
                    }
                } else {
                    Button {
                        if let message = model.auth.configurationMessage { loginError = message; return }
                        Task { do { try await model.auth.signIn() } catch { loginError = error.localizedDescription } }
                    } label: {
                        HStack {
                            Text(model.auth.isSigningIn ? "正在打开 Google…" : "登录 Google")
                            Spacer()
                            if model.auth.isSigningIn { ProgressView() }
                        }
                    }.disabled(model.auth.isSigningIn)
                    if model.auth.configurationMessage != nil {
                        Button("Google 登录配置说明", systemImage: "info.circle") { showLoginHelp = true }
                    }
                }
            }
            Section {
                Picker("下载方式", selection: $model.engine) {
                    ForEach(DownloadEngineKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("当前直连 IP", value: model.directIP.isEmpty ? "尚未选择" : model.directIP)
                    .textSelection(.enabled)
                TextField("添加候选 IP，每行一个", text: $model.candidateText, axis: .vertical)
                    .lineLimit(2...5).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("导入 IP 列表", systemImage: "square.and.arrow.down") { importing = true }.disabled(model.scanning)
                if model.scanning {
                    if model.scanTotal > 0 {
                        ProgressView(value: Double(model.scanCompleted), total: Double(model.scanTotal))
                        Text("已检测 \(model.scanCompleted)/\(model.scanTotal)").font(.caption).monospacedDigit()
                    } else { ProgressView("正在获取候选…") }
                    Button("取消检测", role: .cancel) { model.cancelScan() }
                } else {
                    Button("验证 / 自动扫描 IP", systemImage: "network") { Task { await model.scan() } }
                }
            } header: { Text("网络") } footer: {
                Text("自动检测内置候选、Google DNS 结果和历史 IP。系统后台模式使用正常域名网络；固定 IP 模式使用选定端点。")
            }
            if !model.builtInCandidates.isEmpty {
                Section("上游内置候选") {
                    ForEach(model.builtInCandidates, id: \.self) { Text($0).font(.body.monospaced()).textSelection(.enabled) }
                    Text("候选地址需要在当前网络重新检测，内置不代表可用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !model.endpoints.isEmpty {
                Section("IP 检测结果") {
                    ForEach(model.endpoints) { endpoint in
                        Button { model.selectEndpoint(endpoint) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(endpoint.ip).font(.body.monospaced())
                                    Spacer()
                                    if endpoint.ip == model.directIP { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
                                    if let latency = endpoint.latencyMS { Text("\(latency) ms").font(.caption).foregroundStyle(.secondary) }
                                }
                                Text(endpoint.available ? (endpoint.downloadVerified ? "已验证 API 和测试下载" : "接口可连接，测试下载未验证") : (endpoint.error ?? "检测未通过"))
                                    .font(.caption).foregroundStyle(endpoint.available ? Color.secondary : Color.red)
                                    .multilineTextAlignment(.leading)
                            }
                        }.buttonStyle(.plain).disabled(!endpoint.available)
                    }
                }
            }
            Section {
                Toggle("允许检测剪贴板链接", isOn: $model.clipboardDetectionEnabled)
            } header: { Text("剪贴板") } footer: {
                Text("开启后，回到 App 时只检测是否可能有链接；点击“粘贴”才读取内容。不会在后台读取或上传剪贴板。")
            }
            Section("提醒") {
                Button("允许下载完成通知") { Task { await TransferNotifications.requestPermission() } }
            }
            if let notice = model.notice { Section { Text(notice).textSelection(.enabled) } }
            Section { LabeledContent("版本", value: "0.2.0") }
        }
        .navigationTitle("设置")
        .alert("无法登录 Google", isPresented: Binding(get: { loginError != nil }, set: { if !$0 { loginError = nil } })) {
            if model.auth.configurationMessage != nil { Button("查看配置说明") { showLoginHelp = true } }
            Button("好", role: .cancel) { loginError = nil }
        } message: { Text(loginError ?? "") }
        .sheet(isPresented: $showLoginHelp) { GoogleLoginHelpView(configuration: model.auth.oauthConfiguration) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .json]) { result in
            do { try model.importCandidates(from: result.get()) } catch { model.notice = error.localizedDescription }
        }
    }
}
