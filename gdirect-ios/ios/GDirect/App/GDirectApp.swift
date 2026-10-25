import GoogleSignIn
import Network
import SwiftUI
import UIKit

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    let auth = GoogleAuthService()
    var coordinator: DownloadCoordinator?
    var startupError: String?
    var engine: DownloadEngineKind = DownloadEngineKind(rawValue: UserDefaults.standard.string(forKey: "downloadEngine") ?? "") ?? .system {
        didSet { UserDefaults.standard.set(engine.rawValue, forKey: "downloadEngine") }
    }
    var directIP: String = UserDefaults.standard.string(forKey: "directIP") ?? ""
    var candidateText: String = UserDefaults.standard.string(forKey: "candidateText") ?? "" {
        didSet { UserDefaults.standard.set(candidateText, forKey: "candidateText") }
    }
    var endpoints: [DirectEndpoint] = []
    var builtInCandidates: [String] = []
    var scanning = false
    var scanCompleted: Int64 = 0
    var scanTotal: Int64 = 0
    var notice: String?
    var clipboardDetectionEnabled = UserDefaults.standard.bool(forKey: "clipboardDetectionEnabled") {
        didSet {
            UserDefaults.standard.set(clipboardDetectionEnabled, forKey: "clipboardDetectionEnabled")
            if !clipboardDetectionEnabled { clipboardHasLink = false }
        }
    }
    var clipboardHasLink = false
    private var store: TaskStore?
    private var scanCancellation: NativeCancellation?
    private let pathMonitor = NWPathMonitor()
    private var sawInitialPath = false

    private init() {
        do {
            let store = try TaskStore()
            self.store = store
            endpoints = try store.loadEndpoints()
            coordinator = try DownloadCoordinator(store: store, auth: auth)
        } catch { startupError = error.localizedDescription }
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard self.sawInitialPath else { self.sawInitialPath = true; return }
                    self.scanCancellation?.cancel()
                    self.directIP = ""
                    UserDefaults.standard.removeObject(forKey: "directIP")
                    for index in self.endpoints.indices {
                        self.endpoints[index].available = false
                        self.endpoints[index].error = "网络已变化，请重新检测。"
                    }
                    try? self.store?.saveEndpoints(self.endpoints)
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "org.gdirect.network"))
    }
    func loadBuiltInCandidates() async {
        guard builtInCandidates.isEmpty else { return }
        if let result = try? await NativeCore.call(["command": "candidates"]), let ips = result["candidates"] as? [String] { builtInCandidates = ips }
    }
    func checkClipboard() {
        guard clipboardDetectionEnabled else { clipboardHasLink = false; return }
        // Pattern detection does not read or upload the clipboard contents. Actual paste needs a user tap.
        UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { [weak self] result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.clipboardDetectionEnabled else { return }
                    if case let .success(patterns) = result { self.clipboardHasLink = patterns.contains(.probableWebURL) }
                    else { self.clipboardHasLink = false }
                }
            }
        }
    }
    func selectEndpoint(_ endpoint: DirectEndpoint) {
        guard endpoint.available else { return }
        directIP = endpoint.ip
        UserDefaults.standard.set(endpoint.ip, forKey: "directIP")
    }
    func importCandidates(from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_048_577) ?? Data()
        guard data.count <= 1_048_576, let text = String(data: data, encoding: .utf8) else { throw AppFailure(message: "请导入不超过 1 MiB 的 UTF-8 IP 列表。") }
        let ips = try EndpointImportParser.parse(text)
        candidateText = ips.joined(separator: "\n")
        notice = "已导入 \(ips.count) 个候选 IP，请点击检测。"
    }
    func cancelScan() { scanCancellation?.cancel() }
    func scan() async {
        guard !scanning else { return }
        scanning = true
        scanCompleted = 0
        scanTotal = 0
        notice = nil
        let cancellation = NativeCancellation()
        scanCancellation = cancellation
        defer { scanning = false; scanCancellation = nil }
        do {
            let manual = candidateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : try EndpointImportParser.parse(candidateText)
            var seen = Set<String>()
            let candidates = (manual + endpoints.map(\.ip)).filter { seen.insert($0).inserted }
            guard candidates.count <= 256 else { throw AppFailure(message: "手动候选和缓存合计不能超过 256 个 IP。") }
            let output = try await NativeCore.call(["command": "scan", "candidates": candidates, "include_defaults": true], cancellation: cancellation) { [weak self] done, total in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.scanCompleted = done; self?.scanTotal = total } }
            }
            guard !cancellation.isCancelled else { return }
            let rows = output["endpoints"] as? [[String: Any]] ?? []
            endpoints = rows.compactMap { row in
                guard let ip = row["ip"] as? String else { return nil }
                return DirectEndpoint(ip: ip, available: row["available"] as? Bool ?? false, latencyMS: row["latency_ms"] as? Int,
                    downloadVerified: row["download_verified"] as? Bool ?? false, error: row["error"] as? String, checkedAt: Date())
            }
            try store?.saveEndpoints(endpoints)
            if let selected = endpoints.first(where: { $0.available }) {
                selectEndpoint(selected)
                notice = "检测完成：\(endpoints.filter { $0.available }.count)/\(endpoints.count) 个候选可连接。"
            } else {
                directIP = ""
                UserDefaults.standard.removeObject(forKey: "directIP")
                notice = "当前候选均未通过检测。请查看各 IP 的失败原因，或导入其他候选；启用 VPN/TUN 时请确认直连规则。"
            }
        } catch { notice = cancellation.isCancelled ? "已取消检测。" : error.localizedDescription }
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
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            Group {
                if let error = model.startupError {
                    ContentUnavailableView("无法打开下载记录", systemImage: "externaldrive.badge.exclamationmark", description: Text(error))
                } else {
                    RootView(model: model)
                }
            }
            .task { await model.auth.restore(); await model.loadBuiltInCandidates(); model.checkClipboard() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { model.checkClipboard() } }
            .onChange(of: model.clipboardDetectionEnabled) { _, _ in model.checkClipboard() }
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
