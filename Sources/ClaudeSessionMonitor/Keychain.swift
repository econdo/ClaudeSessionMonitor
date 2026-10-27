import Foundation
import Security

/// Guarda los tokens de cada cuenta en el llavero de macOS (un elemento por cuenta).
enum Keychain {
    private static let service = "com.econdo.ClaudeSessionMonitor.oauth"

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Llavero: \(SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)")"
        }
    }

    private static func query(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }

    static func save(_ tokens: OAuthTokens, for id: UUID) throws {
        let data = try JSONEncoder().encode(tokens)
        let status = SecItemUpdate(query(for: id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(for: id)
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Claude Session Monitor"
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    static func load(_ id: UUID) -> OAuthTokens? {
        var item = query(for: id)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    static func delete(_ id: UUID) {
        SecItemDelete(query(for: id) as CFDictionary)
    }
}
