// Keychain-backed storage for the user's Anthropic API key. The key never touches
// UserDefaults, files, or logs. Resolution order for coaching: env var (dev builds
// launched with simctl --setenv) → Keychain (user-entered in Settings).
import Foundation
import Security
import SwingKit

enum APIKeyStore {
    private static let service = "com.swingthrough.anthropic-api-key"
    private static let account = "default"

    static func save(_ key: String) {
        delete()
        guard !key.isEmpty, let data = key.data(using: .utf8) else { return }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static var hasKey: Bool { load() != nil }
}

/// The app's key chain: environment (dev) → Keychain (user-entered).
struct AppAPIKeyProvider: APIKeyProvider {
    func apiKey() -> String? {
        EnvironmentAPIKeyProvider().apiKey() ?? APIKeyStore.load()
    }
}
