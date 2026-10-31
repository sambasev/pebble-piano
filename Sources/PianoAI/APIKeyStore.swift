import Foundation
#if canImport(Security)
import Security
#endif

/// API keys live in the Keychain, never in the repo or UserDefaults. When none is saved,
/// the provider's environment variable is used (for `swift test` and the command line).
public enum APIKeyStore {
    public enum Source: Equatable, Sendable {
        case keychain
        case environment(String)
        case none
    }

    static let service = "com.sambasev.perfectpiano.ai"

    public static func key(for provider: ModelProvider) -> String? {
        if let saved = keychainKey(for: provider) { return saved }
        let env = ProcessInfo.processInfo.environment[provider.keyEnvironmentVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (env?.isEmpty ?? true) ? nil : env
    }

    public static func source(for provider: ModelProvider) -> Source {
        if keychainKey(for: provider) != nil { return .keychain }
        if let env = ProcessInfo.processInfo.environment[provider.keyEnvironmentVariable], !env.isEmpty {
            return .environment(provider.keyEnvironmentVariable)
        }
        return .none
    }

    /// Saves the key, or removes it when `key` is nil or blank.
    public static func setKey(_ key: String?, for provider: ModelProvider) throws {
        #if canImport(Security)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecAttrLabel as String] = "PerfectPiano – \(provider.displayName) key"
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw ModelError.keychain(status) }
        #else
        throw ModelError.keychain(-1)
        #endif
    }

    static func keychainKey(for provider: ModelProvider) -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
        #else
        return nil
        #endif
    }
}
