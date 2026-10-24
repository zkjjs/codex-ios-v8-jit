import Foundation
import QuotaCore

struct OAuthClient {
    // Public client identifier used by the official open-source Codex login flow.
    // This is not a client secret; account/server policy may disallow this flow.
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let http = HTTPClient.shared
    private let issuer = "https://auth.openai.com"

    func requestCode() async throws -> DeviceCode {
        var request = URLRequest(url: URL(string: "\(issuer)/api/accounts/deviceauth/usercode")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": Self.clientID])
        let data = try await http.checked(request)
        return try JSONDecoder().decode(DeviceCode.self, from: data)
    }
    private struct AuthorizedCode: Decodable {
        let authorization_code: String
        let code_verifier: String
    }
    private struct Tokens: Decodable {
        let access_token: String
        let refresh_token: String?
        let id_token: String?
        let expires_in: Double?
    }
    func complete(_ code: DeviceCode) async throws -> AccountCredentials {
        while Date() < code.expiresAt {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(min(code.interval, max(0, code.expiresAt.timeIntervalSinceNow))))
            try Task.checkCancellation()
            guard Date() < code.expiresAt else { break }
            var request = URLRequest(url: URL(string: "\(issuer)/api/accounts/deviceauth/token")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["device_auth_id": code.deviceAuthID, "user_code": code.userCode])
            let (data, response) = try await http.send(request)
            if response.statusCode == 403 || response.statusCode == 404 { continue }
            guard (200..<300).contains(response.statusCode) else {
                throw ServiceError(status: response.statusCode, retryAt: response.statusCode == 429
                    ? Date().addingTimeInterval(RetryPolicy.delay(header: response.value(forHTTPHeaderField: "Retry-After"), now: Date())) : nil)
            }
            let authorized = try JSONDecoder().decode(AuthorizedCode.self, from: data)
            let tokens = try await tokenRequest([
                "grant_type": "authorization_code", "client_id": Self.clientID,
                "code": authorized.authorization_code, "code_verifier": authorized.code_verifier,
                "redirect_uri": "\(issuer)/deviceauth/callback"
            ])
            guard let refresh = tokens.refresh_token, !refresh.isEmpty else {
                throw AppError.message("授权未返回可续期凭证，请重新登录。")
            }
            return makeCredentials(tokens, refreshToken: refresh, existing: nil)
        }
        throw AppError.message("授权码已过期，请重新生成登录码。")
    }
    func refresh(_ current: AccountCredentials) async throws -> AccountCredentials {
        let tokens = try await tokenRequest(["grant_type": "refresh_token", "client_id": Self.clientID, "refresh_token": current.refreshToken])
        return makeCredentials(tokens, refreshToken: tokens.refresh_token ?? current.refreshToken, existing: current)
    }
    private func tokenRequest(_ values: [String: String]) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "\(issuer)/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = values.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: safe)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: safe)!)"
        }.joined(separator: "&")
        request.httpBody = Data(body.utf8)
        let (data, response) = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 400 || response.statusCode == 401 {
                throw AppError.message("授权已失效，请重新登录账号。")
            }
            throw ServiceError(status: response.statusCode, retryAt: response.statusCode == 429
                ? Date().addingTimeInterval(RetryPolicy.delay(header: response.value(forHTTPHeaderField: "Retry-After"), now: Date())) : nil)
        }
        return try JSONDecoder().decode(Tokens.self, from: data)
    }
    private func makeCredentials(_ tokens: Tokens, refreshToken: String, existing: AccountCredentials?) -> AccountCredentials {
        let access = claims(tokens.access_token)
        let identity = claims(tokens.id_token ?? existing?.idToken ?? "")
        let account = access["https://api.openai.com/auth"] as? [String: Any]
            ?? identity["https://api.openai.com/auth"] as? [String: Any]
        let profile = access["https://api.openai.com/profile"] as? [String: Any]
        let expiry = (access["exp"] as? Double).map(Date.init(timeIntervalSince1970:))
            ?? Date().addingTimeInterval(tokens.expires_in ?? 3600)
        return AccountCredentials(sessionID: existing?.sessionID ?? UUID(), accessToken: tokens.access_token,
            refreshToken: refreshToken, idToken: tokens.id_token ?? existing?.idToken,
            accountID: account?["chatgpt_account_id"] as? String ?? existing?.accountID,
            email: identity["email"] as? String ?? profile?["email"] as? String ?? existing?.email,
            expiresAt: expiry)
    }
    // JWT claims are used only for display/routing; API authorization is validated by OpenAI.
    private func claims(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return [:] }
        var text = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let data = Data(base64Encoded: text),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }
}
