import Foundation
import Security

struct AccountCredentials: Codable {
    var sessionID: UUID
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var accountID: String?
    var email: String?
    var expiresAt: Date
}

struct WidgetGrant: Codable {
    let sessionID: UUID
    let accessToken: String
    let accountID: String?
    let expiresAt: Date
}

enum SecureStore {
    private static let service = "com.zkjjs.codexquota"
    static var sharedGroup: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SharedKeychainGroup") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }
    private static func query(_ key: String, shared: Bool) throws -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: key]
        if shared {
            guard let group = sharedGroup else { throw AppError.message("签名未配置共享钥匙串，小组件暂不可用。") }
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }
    static func read<T: Decodable>(_ key: String, shared: Bool = false) throws -> T? {
        var q = try query(key, shared: shared)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else {
            throw AppError.message("无法读取安全凭证（\(status)），请解锁设备并检查签名权限。")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func save<T: Encodable>(_ value: T, key: String, shared: Bool = false) throws {
        let q = try query(key, shared: shared)
        let attrs: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(value),
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            attrs.forEach { add[$0.key] = $0.value }
            let result = SecItemAdd(add as CFDictionary, nil)
            guard result == errSecSuccess else { throw AppError.message("无法保存安全凭证（\(result)）。") }
        } else if status != errSecSuccess { throw AppError.message("无法更新安全凭证（\(status)）。") }
    }
    static func delete(_ key: String, shared: Bool = false) throws {
        let q = try query(key, shared: shared)
        let status = SecItemDelete(q as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.message("无法清除安全凭证（\(status)），请解锁后重试。")
        }
    }
    static func saveWidgetGrant(_ credentials: AccountCredentials) throws {
        try save(WidgetGrant(sessionID: credentials.sessionID, accessToken: credentials.accessToken,
                             accountID: credentials.accountID, expiresAt: credentials.expiresAt), key: "widget-grant", shared: true)
    }
}
