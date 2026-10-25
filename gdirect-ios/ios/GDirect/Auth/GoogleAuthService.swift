import GoogleSignIn
import Observation
import UIKit

/// GoogleSignIn owns refresh credentials in its Keychain-backed storage; never copy them to SQLite.
@MainActor @Observable
final class GoogleAuthService {
    private(set) var accountID: String?
    private(set) var email: String?
    private let scope = "https://www.googleapis.com/auth/drive.readonly"

    func restore() async {
        guard configured else { return }
        if let user = try? await GIDSignIn.sharedInstance.restorePreviousSignIn() { adopt(user) }
    }
    private var configured: Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else { return false }
        return !value.contains("configure-ios-oauth") && !value.contains("$(")
    }
    func signIn() async throws {
        guard configured else { throw AppFailure(message: "请先配置 Google iOS OAuth 客户端。公开链接下载无需登录。") }
        guard let presenter = Self.presenter else { throw AppFailure(message: "暂时无法打开登录窗口。") }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: [scope])
        adopt(result.user)
        guard result.user.grantedScopes?.contains(scope) == true else { throw AppFailure(message: "需要授予 Drive 只读权限才能浏览云盘。") }
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
