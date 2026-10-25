import Foundation

struct ServerConnection: Codable {
    var server: String
    var accessCode: String

    static let defaultServer = "https://cfinal.com/codex-quota"

    func validatedURL() throws -> URL {
        let cleanServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let components = URLComponents(string: cleanServer),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let url = components.url else { throw QuotaError.invalidConnection }
        return url.appendingPathComponent("v1/quota")
    }
}

enum QuotaError: LocalizedError {
    case invalidConnection, unauthorized, unavailable, invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidConnection: return "请填写 HTTPS 服务器地址和查询码。"
        case .unauthorized: return "查询码不正确或已失效，请重新配对服务器。"
        case .unavailable: return "服务器暂时无法读取 Codex 额度，请稍后重试。"
        case .invalidResponse: return "服务器返回的数据格式不正确。"
        }
    }
}

enum QuotaClient {
    static func fetch(_ connection: ServerConnection) async throws -> QuotaSnapshot {
        try await fetch(connection, timeout: 35)
    }

    static func fetch(_ connection: ServerConnection, timeout: TimeInterval) async throws -> QuotaSnapshot {
        var request = URLRequest(url: try connection.validatedURL())
        request.setValue("Bearer \(connection.accessCode.trimmingCharacters(in: .whitespacesAndNewlines))",
                         forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout
        // Never forward the read code to a redirect destination.
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw QuotaError.invalidResponse }
        if response.statusCode == 401 { throw QuotaError.unauthorized }
        guard response.statusCode == 200 else { throw QuotaError.unavailable }
        guard data.count < 100_000, let value = try? JSONDecoder().decode(QuotaSnapshot.self, from: data),
              value.version == 1 else { throw QuotaError.invalidResponse }
        return value
    }
}

private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
