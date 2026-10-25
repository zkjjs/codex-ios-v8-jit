import GoogleSignIn
import SwiftUI
import UIKit

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    let auth = GoogleAuthService()
    var coordinator: DownloadCoordinator?
    var startupError: String?
    var engine: DownloadEngineKind = .system
    var directIP: String = UserDefaults.standard.string(forKey: "directIP") ?? ""
    var scanning = false
    var notice: String?

    private init() {
        do { coordinator = try DownloadCoordinator(store: TaskStore(), auth: auth) }
        catch { startupError = error.localizedDescription }
    }
    func scan() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        do {
            var request: [String: Any] = ["command": "scan"]
            let candidates = directIP.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
            if !candidates.isEmpty { request["candidates"] = candidates }
            let output = try await NativeCore.call(request)
            guard let endpoints = output["endpoints"] as? [[String: Any]], let ip = endpoints.first?["ip"] as? String else { throw AppFailure(message: "没有可用直连 IP。") }
            directIP = ip
            UserDefaults.standard.set(ip, forKey: "directIP")
            notice = "已验证直连 IP：\(ip)"
        } catch { notice = error.localizedDescription }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = AppModel.shared
        return true
    }
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard let coordinator = AppModel.shared.coordinator, identifier == coordinator.backgroundIdentifier else { completionHandler(); return }
        coordinator.attachBackgroundCompletion(completionHandler)
    }
}

@main @MainActor
struct GDirectApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    var body: some Scene {
        WindowGroup {
            Group {
                if let error = model.startupError {
                    ContentUnavailableView("无法打开下载记录", systemImage: "externaldrive.badge.exclamationmark", description: Text(error))
                } else {
                    RootView(model: model)
                }
            }
            .task { await model.auth.restore() }
            .onOpenURL { url in _ = GIDSignIn.sharedInstance.handle(url) }
        }
    }
}

private struct RootView: View {
    @Bindable var model: AppModel
    var body: some View {
        TabView {
            if let coordinator = model.coordinator {
                NavigationStack { TransfersView(coordinator: coordinator, model: model) }
                    .tabItem { Label("下载", systemImage: "arrow.down.circle") }
                NavigationStack { DriveBrowserView(model: model, folderID: "root", title: "我的云盘") }
                    .tabItem { Label("云盘", systemImage: "folder") }
            }
            NavigationStack { SettingsView(model: model) }
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}

private struct SettingsView: View {
    @Bindable var model: AppModel
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
                    Button("登录 Google") {
                        Task { do { try await model.auth.signIn() } catch { model.notice = error.localizedDescription } }
                    }
                }
            }
            Section {
                Picker("下载方式", selection: $model.engine) {
                    ForEach(DownloadEngineKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("直连 IP / 扫描候选 IP", text: $model.directIP)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(model.scanning ? "正在验证…" : "验证 / 自动扫描 IP") { Task { await model.scan() } }
                    .disabled(model.scanning)
            } header: { Text("网络") } footer: {
                Text("系统后台下载使用正常域名网络。固定 IP 模式保留直连能力，通过系统持续后台任务运行；系统结束任务后可继续断点下载。")
            }
            Section("提醒") {
                Button("允许下载完成通知") { Task { await TransferNotifications.requestPermission() } }
            }
            if let notice = model.notice { Section { Text(notice).textSelection(.enabled) } }
        }
        .navigationTitle("设置")
    }
}
