import Foundation

public struct PairingPayload: Codable, Sendable {
    public let serverURL: String
    public let gatewayKey: String
    public let certificateSHA256: String
    enum CodingKeys: String, CodingKey {
        case serverURL = "server_url", gatewayKey = "gateway_key", certificateSHA256 = "certificate_sha256"
    }
    public func validatedURL() throws -> URL {
        guard let url = URL(string: serverURL), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", gatewayKey.count >= 32,
              certificateSHA256.count == 64,
              certificateSHA256.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw PairingError.invalid
        }
        return url
    }
}
public enum PairingError: LocalizedError {
    case invalid
    public var errorDescription: String? { "配对内容不完整：需要 HTTPS 地址、配对密钥和 64 位证书指纹。" }
}
