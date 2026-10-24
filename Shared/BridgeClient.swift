import Foundation
import Security
import CryptoKit
import QuotaCore

struct ServerProfile: Codable {
    var sessionID: UUID
    let serverURL: URL
    let gatewayKey: String
    let certificateSHA256: String
    func rotated() -> ServerProfile { var result = self; result.sessionID = UUID(); return result }
    init(pairing text: String) throws {
        let data = try JSONDecoder().decode(PairingPayload.self, from: Data(text.utf8))
        serverURL = try data.validatedURL()
        gatewayKey = data.gatewayKey
        certificateSHA256 = data.certificateSHA256.lowercased()
        sessionID = UUID()
    }
}

private final class PinnedServerDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let profile: ServerProfile
    init(_ profile: ServerProfile) { self.profile = profile }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        #if DEBUG
        print("Bridge TLS challenge", challenge.protectionSpace.host, challenge.protectionSpace.port)
        #endif
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.lowercased() == profile.serverURL.host?.lowercased(),
              challenge.protectionSpace.port == (profile.serverURL.port ?? 443),
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
        guard digest == profile.certificateSHA256 else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        // Trust this explicitly paired certificate, while retaining date and hostname validation.
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, profile.serverURL.host! as CFString))
        SecTrustSetAnchorCertificates(trust, [leaf] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        SecTrustSetNetworkFetchAllowed(trust, false)
        #if DEBUG
        print("Bridge TLS evaluating paired certificate")
        #endif
        guard SecTrustEvaluateWithError(trust, nil) else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        #if DEBUG
        print("Bridge TLS certificate accepted")
        #endif
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward the pairing secret through a redirect.
    }
}

struct BridgeClient {
    let profile: ServerProfile
    var timeout: TimeInterval = 55
    func request(_ path: String, method: String = "GET", body: [String: String]? = nil) async throws -> (Data, Int) {
        guard profile.serverURL.scheme == "https", profile.serverURL.host != nil else {
            throw AppError.message("服务器地址必须为 HTTPS。")
        }
        let url = profile.serverURL.appendingPathComponent(path)
        let delegate = PinnedServerDelegate(profile)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 10
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(profile.gatewayKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError {
            throw AppError.message("连接服务器失败（\(error.code.rawValue)）：\(error.localizedDescription)")
        }
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 429 {
            throw ServiceError(status: 429, retryAt: Date().addingTimeInterval(RetryPolicy.delay(header: response.value(forHTTPHeaderField: "Retry-After"), now: Date())))
        }
        guard (200..<300).contains(response.statusCode) else {
            struct Failure: Decodable { let message: String? }
            if response.statusCode == 409 { throw ServiceError(status: 409, retryAt: nil) }
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.message
            throw AppError.message(message ?? "服务器返回 HTTP \(response.statusCode)。")
        }
        return (data, response.statusCode)
    }
    func startLogin() async throws -> DeviceCode {
        let (data, _) = try await request("v1/login/start", method: "POST", body: [:])
        return try JSONDecoder().decode(DeviceCode.self, from: data)
    }
    func finishLogin(_ code: DeviceCode) async throws {
        while Date() < code.expiresAt {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(code.interval))
            let (_, status) = try await request("v1/login/poll", method: "POST", body: ["flow_id":code.deviceAuthID])
            if status == 200 { return }
        }
        throw AppError.message("授权码已过期，请重新登录。")
    }
    func usage() async throws -> QuotaSnapshot {
        let (data, _) = try await request("v1/usage")
        return try JSONDecoder().decode(UsageResponse.self, from: data).snapshot(at: Date())
    }
}
