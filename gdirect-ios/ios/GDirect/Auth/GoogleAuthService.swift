import GoogleSignIn
import Observation
import UIKit

/// GoogleSignIn owns refresh credentials in its Keychain-backed storage; never copy them to SQLite.
@MainActor @Observable
final class GoogleAuthService {
    private(set) var accountID: String?
    private(set) var email: String?
    private(set) var isSigningIn = false
    private let scope = "https://www.googleapis.com/auth/drive.readonly"

    func restore() async {
        guard configured else { return }
        if let user = try? await GIDSignIn.sharedInstance.restorePreviousSignIn() { adopt(user) }
    }
    var oauthConfiguration: OAuthClientConfiguration {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return OAuthClientConfiguration(
            clientID: Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? "",
            expectedBundleID: Bundle.main.object(forInfoDictionaryKey: "GDIRECTOAuthBundleID") as? String ?? "",
            actualBundleID: Bundle.main.bundleIdentifier ?? "",
            callbackSchemes: types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] })
    }
    var configurationMessage: String? {
        switch oauthConfiguration.issue {
        case .missingClientID: "此安装包尚未配置 Google 登录。需要为 gdirect 配置有效的 iOS OAuth 客户端 ID。"
        case .bundleMismatch: "重新签名后的 App 标识与 Google 登录配置不一致。请使用匹配当前 App 标识的 OAuth 配置重新编译。"
        case .missingCallbackScheme: "Google 登录回调未正确配置，请重新编译安装包。"
        case nil: nil
        }
    }
    private var configured: Bool { oauthConfiguration.issue == nil }
    func signIn() async throws {
        guard !isSigningIn else { return }
        if let message = configurationMessage { throw AppFailure(message: message) }
        guard let presenter = Self.presenter else { throw AppFailure(message: "暂时无法打开登录窗口，请回到 App 前台重试。") }
        isSigningIn = true
        defer { isSigningIn = false }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: oauthConfiguration.clientID)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: [scope])
            guard result.user.grantedScopes?.contains(scope) == true else { throw AppFailure(message: "需要授予 Drive 只读权限才能浏览云盘。") }
            adopt(result.user)
        } catch {
            let nsError = error as NSError
            if nsError.domain == kGIDSignInErrorDomain && nsError.code == -5 { return }
            if nsError.domain == kGIDSignInErrorDomain && nsError.code == -2 {
                throw AppFailure(message: "Google 登录凭据无法保存到钥匙串。请检查安装包签名是否保留了钥匙串权限。")
            }
            if nsError.domain == NSURLErrorDomain { throw AppFailure(message: "无法连接 Google 登录服务，请检查网络后重试。") }
            if let failure = error as? AppFailure { throw failure }
            throw AppFailure(message: "Google 授权未完成（错误码 \(nsError.code)）。请检查 OAuth 测试账户和网络后重试。")
        }
    }
    func accessToken(accountID: String) async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser, user.userID == accountID else { throw AppFailure(message: "请先登录此下载任务所属的 Google 账户。") }
        let refreshed = try await user.refreshTokensIfNeeded()
        return refreshed.accessToken.tokenString
    }
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        accountID = nil
        email = nil
    }
    private func adopt(_ user: GIDGoogleUser) { accountID = user.userID; email = user.profile?.email }
    private static var presenter: UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var controller = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}
