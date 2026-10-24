import Foundation
import QuotaCore

struct ServiceError: LocalizedError {
    let status: Int
    let retryAt: Date?
    var errorDescription: String? {
        switch status {
        case 401: return "登录已失效，请重新登录。"
        case 403: return "服务拒绝访问。请检查账号是否已开启设备码登录，或稍后更换可用网络重试。"
        case 404: return "当前授权方式或额度接口暂不可用。"
        case 429: return "请求过于频繁，已暂停刷新，稍后会重试。"
        default: return "服务暂时不可用（HTTP \(status)）。"
        }
    }
}

struct HTTPClient {
    static let shared = HTTPClient()
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config)
    }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
    func checked(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            let retry = response.statusCode == 429
                ? Date().addingTimeInterval(RetryPolicy.delay(header: response.value(forHTTPHeaderField: "Retry-After"), now: Date())) : nil
            throw ServiceError(status: response.statusCode, retryAt: retry)
        }
        return data
    }
    func usage(accessToken: String, accountID: String?) async throws -> QuotaSnapshot {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let accountID, !accountID.isEmpty { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let data = try await checked(request)
        do { return try JSONDecoder().decode(UsageResponse.self, from: data).snapshot(at: Date()) }
        catch { throw AppError.message("额度接口返回了暂不支持的数据格式，请稍后更新应用。") }
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
