import Foundation
import Observation
import WidgetKit
import QuotaCore

@MainActor @Observable
final class QuotaStore {
    private(set) var snapshot: QuotaSnapshot?
    private(set) var serverProfile: ServerProfile?
    private(set) var deviceCode: DeviceCode?
    private(set) var isLoggingIn = false
    private(set) var isRefreshing = false
    private(set) var isSignedIn = false
    var message: String?
    private(set) var sharingWarning: String?
    private(set) var retryAt: Date?
    var privacyHidden = false
    private var generation = UUID()
    private var loginTask: Task<Void,Never>?
    private let cache = SnapshotStore.shared
    init() {
        do {
            serverProfile = try SecureStore.read("server-profile")
            if let profile = serverProfile {
                try? cache.begin(sessionID: profile.sessionID)
                if let state = try? cache.read(), state.sessionID == profile.sessionID {
                    snapshot = state.snapshot; retryAt = state.retryAt; privacyHidden = state.privacyHidden
                    isSignedIn = snapshot != nil
                }
            }
        } catch { message = error.localizedDescription }
        if !cache.available { sharingWarning = "当前签名不支持小组件共享。需保留 App Groups、共享钥匙串和 Widget 扩展。" }
    }
    func pair(_ text: String) throws {
        let profile = try ServerProfile(pairing: text)
        try SecureStore.save(profile,key:"server-profile")
        try? SecureStore.delete("account")
        try? SecureStore.delete("widget-grant",shared:true)
        cancelLogin(); isRefreshing = false
        serverProfile = profile; snapshot = nil; isSignedIn = false; retryAt = nil; message = nil
        do {
            try cache.begin(sessionID: profile.sessionID)
            try SecureStore.save(profile,key:"server-profile",shared:true)
            sharingWarning = nil
        } catch { sharingWarning = "服务器已配对，但小组件共享不可用：\(error.localizedDescription)" }
        WidgetCenter.shared.reloadAllTimelines()
    }
    func startLogin() {
        guard !isLoggingIn, retryAt.map({ $0 <= Date() }) ?? true else { return }
        guard let profile = serverProfile else { message = "请先在设置中连接你的日本服务器。"; return }
        generation = UUID(); let attempt = generation
        isLoggingIn = true; message = nil
        loginTask = Task {
            defer { if generation == attempt { isLoggingIn = false; deviceCode = nil } }
            do {
                let client = BridgeClient(profile:profile)
                let code = try await client.startLogin()
                guard generation == attempt, !Task.isCancelled else { return }
                deviceCode = code
                try await client.finishLogin(code)
                guard generation == attempt, !Task.isCancelled else { return }
                isSignedIn = true
                await refresh()
            } catch is CancellationError { }
            catch {
                guard generation == attempt else { return }
                message = error.localizedDescription
                retryAt = (error as? ServiceError)?.retryAt
            }
        }
    }
    func cancelLogin() {
        generation = UUID(); loginTask?.cancel(); loginTask = nil; deviceCode = nil; isLoggingIn = false
    }
    func refresh() async {
        guard !isRefreshing, let profile = serverProfile else { return }
        if let state = try? cache.read(), state.sessionID == profile.sessionID {
            if let newer = state.snapshot, snapshot == nil || newer.fetchedAt > snapshot!.fetchedAt { snapshot = newer }
            retryAt = state.retryAt ?? retryAt
        }
        guard retryAt.map({ $0 <= Date() }) ?? true else { return }
        let attempt = generation; isRefreshing = true
        defer { if generation == attempt { isRefreshing = false } }
        do {
            let fresh = try await BridgeClient(profile:profile).usage()
            guard generation == attempt, !Task.isCancelled else { return }
            snapshot = fresh; isSignedIn = true; message = nil; retryAt = nil
            do {
                try cache.write(fresh,sessionID:profile.sessionID)
                let state = try cache.read()
                if state.sessionID == profile.sessionID {
                    retryAt = state.retryAt
                    if retryAt.map({ $0 > Date() }) == true { message = state.message }
                }
            } catch { sharingWarning = error.localizedDescription }
            WidgetCenter.shared.reloadAllTimelines()
        } catch is CancellationError { }
        catch {
            guard generation == attempt else { return }
            if let service = error as? ServiceError, service.status == 409 {
                isSignedIn = false; snapshot = nil; message = "服务器已连接，请登录 ChatGPT 账号。"
                rotateSession(profile)
            } else {
                message = error.localizedDescription
                retryAt = (error as? ServiceError)?.retryAt
                try? cache.failure(message ?? "刷新失败",retryAt:retryAt,sessionID:profile.sessionID)
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    func setPrivacy(_ hidden: Bool) {
        privacyHidden = hidden
        do { try cache.update { $0.privacyHidden = hidden } } catch { sharingWarning = error.localizedDescription }
        WidgetCenter.shared.reloadAllTimelines()
    }
    private func rotateSession(_ previous: ServerProfile) {
        let current = previous.rotated()
        serverProfile = current
        do {
            // New UUID atomically invalidates completions from pre-logout widget requests.
            try cache.begin(sessionID:current.sessionID)
            try SecureStore.save(current,key:"server-profile")
            try SecureStore.save(current,key:"server-profile",shared:true)
        } catch {
            // Preserve the private profile even if this signature cannot share widget data.
            try? SecureStore.save(current,key:"server-profile")
            sharingWarning = "账号状态已更新，小组件同步不可用：\(error.localizedDescription)"
        }
    }
    func logout() async {
        guard let profile = serverProfile else { return }
        cancelLogin(); isRefreshing = false
        let attempt = generation
        do {
            _ = try await BridgeClient(profile:profile).request("v1/logout",method:"POST",body:[:])
            guard attempt == generation else { return }
            isSignedIn = false; snapshot = nil; retryAt = nil; message = nil
            rotateSession(profile)
            WidgetCenter.shared.reloadAllTimelines()
        } catch { message = "退出未完成：\(error.localizedDescription)" }
    }
}
