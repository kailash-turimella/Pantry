import Foundation
import Security

/// Where the Anthropic API key comes from, in priority order:
///
/// 1. **Keychain** — what you type into Settings. Encrypted at rest, excluded
///    from iCloud Keychain sync and from backups restored onto another device,
///    and readable only while the phone is unlocked.
/// 2. **`ANTHROPIC_API_KEY` env var** — set it in the Xcode scheme while
///    developing, so a wiped simulator doesn't mean retyping the key.
///
/// There is deliberately no on-disk copy bundled into the app: a key sitting in
/// a plist inside the `.app` is readable by anyone holding the bundle, with no
/// jailbreak and no decryption required.
enum APIKeyStore {
    private static let service = "com.kailash.Pantry"
    private static let account = "anthropic-api-key"

    // MARK: - Reading

    static var current: String? {
        if let stored = keychainValue(), !stored.isEmpty { return stored }
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty { return env }
        return nil
    }

    static var hasKey: Bool { current != nil }

    /// Describes where the active key came from, for the Settings screen.
    static var sourceDescription: String {
        if let stored = keychainValue(), !stored.isEmpty { return "Keychain" }
        if ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil { return "Environment variable" }
        return "Not set"
    }

    static func requireKey() throws -> String {
        guard let key = current else { throw ClaudeError.missingAPIKey }
        return key
    }

    /// `sk-ant-...abcd` — safe to show on screen.
    static func redacted(_ key: String) -> String {
        guard key.count > 12 else { return "••••" }
        return "\(key.prefix(7))…\(key.suffix(4))"
    }

    // MARK: - Writing

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return clear() }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func clear() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Sources

    private static func keychainValue() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

}
