import Foundation
import Observation
import WidgetKit
import QuotaCore

@MainActor @Observable
final class QuotaStore {
    private(set) var snapshot: QuotaSnapshot?
    private(set) var credentials: AccountCredentials?
    private(set) var deviceCode: DeviceCode?
    private(set) var isLoggingIn = false
    private(set) var isRefreshing = false
    var message: String?
    private(set) var sharingWarning: String?
    private(set) var retryAt: Date?
    var privacyHidden = false
    private var generation = UUID()
    private var loginTask: Task<Void, Never>?
    private let auth = OAuthClient()
    private let cache = SnapshotStore.shared
    var isSignedIn: Bool { credentials != nil }

    init() {
        do {
            credentials = try SecureStore.read("account")
            if let credentials {
                try? cache.begin(sessionID: credentials.sessionID)
                if let state = try? cache.read(), state.sessionID == credentials.sessionID {
                    snapshot = state.snapshot
                    retryAt = state.retryAt
                    privacyHidden = state.privacyHidden
                }
            }
        } catch { message = error.localizedDescription }
        if !cache.available { sharingWarning = "当前签名不支持小组件共享。需保留 App Groups、共享钥匙串和 Widget 扩展。" }
    }
    func startLogin() {
        guard !isLoggingIn, retryAt.map({ $0 <= Date() }) ?? true else { return }
        generation = UUID()
        let attempt = generation
        isLoggingIn = true
        message = nil
        loginTask = Task {
            defer { if generation == attempt { isLoggingIn = false; deviceCode = nil } }
            do {
                let code = try await auth.requestCode()
                guard generation == attempt, !Task.isCancelled else { return }
                deviceCode = code
                let account = try await auth.complete(code)
                guard generation == attempt, !Task.isCancelled else { return }
                try SecureStore.save(account, key: "account")
                credentials = account
                snapshot = nil
                retryAt = nil
                publishCredentials(account)
                await refresh()
            } catch is CancellationError { }
            catch {
                guard generation == attempt else { return }
                message = readable(error)
                if let service = error as? ServiceError { retryAt = service.retryAt }
            }
        }
    }
    func cancelLogin() {
        generation = UUID()
        loginTask?.cancel()
        loginTask = nil
        deviceCode = nil
        isLoggingIn = false
    }
    func refresh() async {
        guard !isRefreshing, var account = credentials else { return }
        // Shared throttling also applies after returning from the widget.
        if let state = try? cache.read(), state.sessionID == account.sessionID {
            if let newer = state.snapshot, snapshot == nil || newer.fetchedAt > snapshot!.fetchedAt { snapshot = newer }
            retryAt = state.retryAt ?? retryAt
        }
        guard retryAt.map({ $0 <= Date() }) ?? true else { return }
        let attempt = generation
        isRefreshing = true
        defer { if generation == attempt { isRefreshing = false } }
        do {
            if account.expiresAt.timeIntervalSinceNow < 120 {
                account = try await auth.refresh(account)
                guard generation == attempt, !Task.isCancelled else { return }
                try SecureStore.save(account, key: "account")
                credentials = account
                publishCredentials(account)
            }
            let fresh: QuotaSnapshot
            do { fresh = try await HTTPClient.shared.usage(accessToken: account.accessToken, accountID: account.accountID) }
            catch let service as ServiceError where service.status == 401 {
                account = try await auth.refresh(account)
                guard generation == attempt, !Task.isCancelled else { return }
                try SecureStore.save(account, key: "account")
                credentials = account
                publishCredentials(account)
                fresh = try await HTTPClient.shared.usage(accessToken: account.accessToken, accountID: account.accountID)
            }
            guard generation == attempt, !Task.isCancelled else { return }
            snapshot = fresh
            message = nil
            retryAt = nil
            do {
                try cache.write(fresh, sessionID: account.sessionID)
                let state = try cache.read()
                if state.sessionID == account.sessionID {
                    retryAt = state.retryAt
                    if retryAt.map({ $0 > Date() }) == true { message = state.message }
                }
            } catch { sharingWarning = error.localizedDescription }
            WidgetCenter.shared.reloadAllTimelines()
        } catch is CancellationError { }
        catch {
            guard generation == attempt else { return }
            message = readable(error)
            retryAt = (error as? ServiceError)?.retryAt
            try? cache.failure(message ?? "刷新失败", retryAt: retryAt, sessionID: account.sessionID)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    private func publishCredentials(_ account: AccountCredentials) {
        do {
            try cache.begin(sessionID: account.sessionID)
            try SecureStore.saveWidgetGrant(account)
            sharingWarning = nil
        } catch { sharingWarning = "应用可使用，但小组件同步不可用：\(error.localizedDescription)" }
    }
    func setPrivacy(_ hidden: Bool) {
        privacyHidden = hidden
        do { try cache.update { $0.privacyHidden = hidden } }
        catch { sharingWarning = error.localizedDescription }
        WidgetCenter.shared.reloadAllTimelines()
    }
    func logout() {
        cancelLogin()
        isRefreshing = false
        do { try SecureStore.delete("account") }
        catch { message = "退出未完成：\(error.localizedDescription)"; return }
        credentials = nil
        snapshot = nil
        retryAt = nil
        var warnings: [String] = []
        do { try cache.clear() } catch { warnings.append(error.localizedDescription) }
        do { try SecureStore.delete("widget-grant", shared: true) } catch { warnings.append(error.localizedDescription) }
        message = warnings.isEmpty ? nil : "账号已退出，小组件清理遇到问题：" + warnings.joined(separator: "；")
        WidgetCenter.shared.reloadAllTimelines()
    }
    private func readable(_ error: Error) -> String {
        if error is DecodingError { return "服务返回格式已变化，请更新应用或稍后重试。" }
        if let urlError = error as? URLError {
            return urlError.code == .notConnectedToInternet ? "网络未连接，显示上次成功同步的数据。" : "连接失败，请检查网络后重试。"
        }
        return error.localizedDescription
    }
}
