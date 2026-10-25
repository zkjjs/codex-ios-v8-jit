import Foundation
import Security

enum SharedStore {
    static let group = "group.com.zkjjs.codexquota"
    private static let service = "com.zkjjs.codexquota.connection"

    private static var shared: UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil else { return nil }
        return UserDefaults(suiteName: group)
    }

    static var groupAvailable: Bool { shared != nil }

    static func loadConnection() -> ServerConnection? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "server",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = try? JSONDecoder().decode(ServerConnection.self, from: data) { return value }
        return widgetConnection()
    }

    static func saveConnection(_ value: ServerConnection) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "server"]
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw QuotaError.invalidConnection }
        } else if status != errSecSuccess { throw QuotaError.invalidConnection }
        shared?.set(data, forKey: "serverConnection")
    }

    static func widgetConnection() -> ServerConnection? {
        guard let data = shared?.data(forKey: "serverConnection") else { return nil }
        return try? JSONDecoder().decode(ServerConnection.self, from: data)
    }

    static func loadSnapshot() -> QuotaSnapshot? {
        guard let data = shared?.data(forKey: "quotaSnapshot") ?? UserDefaults.standard.data(forKey: "quotaSnapshot") else { return nil }
        return try? JSONDecoder().decode(QuotaSnapshot.self, from: data)
    }

    static func saveSnapshot(_ value: QuotaSnapshot) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: "quotaSnapshot")
        shared?.set(data, forKey: "quotaSnapshot")
    }

    static func clear() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "server"]
        SecItemDelete(query as CFDictionary)
        shared?.removeObject(forKey: "serverConnection")
        shared?.removeObject(forKey: "quotaSnapshot")
        UserDefaults.standard.removeObject(forKey: "quotaSnapshot")
    }
}
