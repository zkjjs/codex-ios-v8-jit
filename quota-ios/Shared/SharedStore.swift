import Foundation
import Security

enum SharedStore {
    static let group = "group.com.zkjjs.codexquota"
    private static let service = "com.zkjjs.codexquota.connection"

    // SideStore may add a signing-team suffix to the original group identifier.
    // Profile/Info metadata only supplies candidates; iOS validates container access.
    private static let sharedGroup: String? = {
        let metadata = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }
        return groupCandidates(metadata: metadata, profile: profile).first {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }
    }()

    private static var shared: UserDefaults? {
        sharedGroup.flatMap { UserDefaults(suiteName: $0) }
    }

    static func groupCandidates(metadata: [String], profile: Data?) -> [String] {
        var profileGroups: [String] = []
        if let data = profile,
           let start = data.range(of: Data("<?xml".utf8)),
           let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
           let value = try? PropertyListSerialization.propertyList(
                from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil),
           let dictionary = value as? [String: Any],
           let entitlements = dictionary["Entitlements"] as? [String: Any] {
            profileGroups = entitlements["com.apple.security.application-groups"] as? [String] ?? []
        }
        var seen = Set<String>()
        // Prefer the signed profile's matching group, never an unrelated certificate group.
        return (profileGroups + metadata + [group]).filter {
            ($0 == group || $0.hasPrefix(group + ".")) && seen.insert($0).inserted
        }
    }

    static var groupAvailable: Bool { shared != nil }

    static func loadConnection() -> ServerConnection? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "server",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = try? JSONDecoder().decode(ServerConnection.self, from: data) {
            // Migrate a previously paired App after installing a build with group support.
            shared?.set(data, forKey: "serverConnection")
            return value
        }
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
