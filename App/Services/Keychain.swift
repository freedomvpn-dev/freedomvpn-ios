import Foundation
import Security

/// Small Keychain wrapper for the session tokens and the per-install HWID secret
/// (Keychain survives app reinstalls, so the panel does not count a reinstall as a new device).
enum Keychain {
    private static let service = "com.topfreedom.vpn"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Random per-install secret for x-hwid.
    static var hwidSecret: String {
        if let saved = get("hwid_secret") { return saved }
        let fresh = UUID().uuidString
        set("hwid_secret", fresh)
        return fresh
    }
}
