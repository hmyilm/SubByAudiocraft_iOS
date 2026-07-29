import Foundation
import Security

enum SecureAPIKeyStore {
    private static let service = Bundle.main.bundleIdentifier
        ?? "com.hmyilm.SubByAudiocraft"
    private static let groqAccount = "cloud.groq.api-key"

    static func loadGroqAPIKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: groqAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return ""
        }
        return key
    }

    @discardableResult
    static func saveGroqAPIKey(_ rawKey: String) -> Bool {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            deleteGroqAPIKey()
            return true
        }
        guard let data = key.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: groqAccount
        ]
        let update: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var insertion = query
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess
    }

    static func deleteGroqAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: groqAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
