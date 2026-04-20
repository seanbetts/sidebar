import Foundation
import Security
import sideBarShared

/// Keychain-backed staging store for pending provider-key secrets.
public final class SettingsPendingSecretStore {
    private let service: String
    private let accessGroup: String?
    private let keychain: KeychainClient
    private let useInMemoryStore: Bool
    private var memorySecrets: [String: Data] = [:]

    public init(
        service: String? = nil,
        accessGroup: String? = nil,
        keychain: KeychainClient = SystemKeychainClient(),
        useInMemoryStore: Bool? = nil
    ) {
        self.service = service ?? AppGroupConfiguration.keychainService
            ?? (Bundle.main.bundleIdentifier ?? "sideBar.SettingsPendingSecretStore")
        self.accessGroup = accessGroup ?? AppGroupConfiguration.keychainAccessGroup
        self.keychain = keychain
        self.useInMemoryStore = useInMemoryStore
            ?? (ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
    }

    public func stage(_ secret: Data) throws -> String {
        let reference = UUID().uuidString
        try save(secret, reference: reference)
        return reference
    }

    public func lookup(reference: String) throws -> Data {
        if useInMemoryStore {
            guard let secret = memorySecrets[reference] else {
                throw SettingsPendingSecretStoreError.missingReference
            }
            return secret
        }

        let query = baseQuery(reference: reference)
        var result: AnyObject?
        let status = keychain.copyMatching(query as CFDictionary, result: &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw SettingsPendingSecretStoreError.missingReference
            }
            return data
        case errSecItemNotFound:
            throw SettingsPendingSecretStoreError.missingReference
        default:
            throw SettingsPendingSecretStoreError.unexpectedStatus(status)
        }
    }

    public func delete(reference: String) throws {
        if useInMemoryStore {
            guard memorySecrets.removeValue(forKey: reference) != nil else {
                throw SettingsPendingSecretStoreError.missingReference
            }
            return
        }

        let query = baseQuery(reference: reference)
        let status = keychain.delete(query as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            throw SettingsPendingSecretStoreError.missingReference
        default:
            throw SettingsPendingSecretStoreError.unexpectedStatus(status)
        }
    }

    private func save(_ secret: Data, reference: String) throws {
        if useInMemoryStore {
            memorySecrets[reference] = secret
            return
        }

        let query = baseQuery(reference: reference)
        var attributes: [String: Any] = [
            kSecValueData as String: secret
        ]
        #if os(iOS)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #endif
        attributes[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any

        let status = keychain.update(query as CFDictionary, attributes: attributes as CFDictionary)
        if status == errSecItemNotFound {
            var create = query
            create[kSecValueData as String] = secret
            #if os(iOS)
            create[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            #endif
            create[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
            let addStatus = keychain.add(create as CFDictionary, result: nil)
            guard addStatus == errSecSuccess else {
                throw SettingsPendingSecretStoreError.unexpectedStatus(addStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw SettingsPendingSecretStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(reference: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain as String: true
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

enum SettingsPendingSecretStoreError: Error {
    case missingReference
    case unexpectedStatus(OSStatus)
}
