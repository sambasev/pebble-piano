import Foundation
#if canImport(Security)
import Security
#endif

/// One-time migration from the standalone tutor; never replaces a shared credential.
public enum LegacyTutorKeyMigration {
    public static func run(defaults: UserDefaults = .standard) throws {
        let marker = "ai.tutor.keyMigrationCompleted"
        guard !defaults.bool(forKey: marker) else { return }
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.sambasev.perfectpiano.tutor", kSecAttrAccount as String: "meta"]
        try migrate(hasSharedKey: { APIKeyStore.key(for: .meta) != nil }, readLegacy: {
            var read = query; read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(read as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = result as? Data else { throw ModelError.keychain(status) }
            return String(data: data, encoding: .utf8)
        }, saveShared: { try APIKeyStore.setKey($0, for: .meta) }, removeLegacy: {
            SecItemDelete(query as CFDictionary)
        })
        defaults.set(true, forKey: marker)
        #endif
    }

    static func migrate(hasSharedKey: () -> Bool, readLegacy: () throws -> String?,
                        saveShared: (String) throws -> Void, removeLegacy: () -> Void) throws {
        guard !hasSharedKey(), let legacy = try readLegacy(),
              !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try saveShared(legacy)
        removeLegacy() // A failed save must leave the original credential available.
    }
}
