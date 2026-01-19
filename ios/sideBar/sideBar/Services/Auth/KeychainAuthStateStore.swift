import Foundation
import Security
import CryptoKit

public enum KeychainError: LocalizedError, Equatable {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Authentication data not found. Please sign in again."
        case .duplicateItem:
            return "Duplicate keychain entry detected."
        case .unexpectedStatus(let status):
            return "Keychain error: \(status)"
        case .invalidData:
            return "Stored authentication data is corrupted."
        }
    }
}

public protocol KeychainClient {
    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus
    func add(_ attributes: CFDictionary, result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

public struct SystemKeychainClient: KeychainClient {
    public init() {
    }

    public func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
        SecItemCopyMatching(query, result)
    }

    public func add(_ attributes: CFDictionary, result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
        SecItemAdd(attributes, result)
    }

    public func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    public func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

public final class KeychainAuthStateStore: AuthStateStore {
    private let service: String
    private let accessGroup: String?
    private let accessTokenAccount = "accessToken"
    private let userIdAccount = "userId"
    private let encryptionKeyAccount = "authEncryptionKey"
    private let useInMemoryStore: Bool
    private let keychain: KeychainClient
    private var memoryStore: [String: String] = [:]
    private var cachedEncryptionKey: SymmetricKey?

    public init(
        service: String? = nil,
        accessGroup: String? = nil,
        keychain: KeychainClient = SystemKeychainClient(),
        useInMemoryStore: Bool? = nil
    ) {
        self.service = service ?? (Bundle.main.bundleIdentifier ?? "sideBar.Auth")
        self.accessGroup = accessGroup
        self.keychain = keychain
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.useInMemoryStore = useInMemoryStore ?? isRunningTests
    }

    public func saveAccessToken(_ token: String?) throws {
        try saveString(token, account: accessTokenAccount)
    }

    public func saveUserId(_ userId: String?) throws {
        try saveString(userId, account: userIdAccount)
    }

    public func loadAccessToken() throws -> String? {
        try loadString(account: accessTokenAccount)
    }

    public func loadUserId() throws -> String? {
        try loadString(account: userIdAccount)
    }

    public func clear() throws {
        try deleteItem(account: accessTokenAccount)
        try deleteItem(account: userIdAccount)
    }

    private func saveString(_ value: String?, account: String) throws {
        if useInMemoryStore {
            if let value {
                memoryStore[account] = value
            } else {
                memoryStore.removeValue(forKey: account)
            }
            return
        }
        guard let value else {
            try deleteItem(account: account)
            return
        }
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        let encryptedData = try encrypt(data)

        let query = baseQuery(account: account)
        var attributes: [String: Any] = [
            kSecValueData as String: encryptedData
        ]
        #if os(iOS)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #endif
        attributes[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any

        let status = keychain.update(query as CFDictionary, attributes: attributes as CFDictionary)
        if status == errSecItemNotFound {
            var create = query
            create[kSecValueData as String] = encryptedData
            #if os(iOS)
            create[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            #endif
            create[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
            let addStatus = keychain.add(create as CFDictionary, result: nil)
            if addStatus != errSecSuccess {
                throw mapStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw mapStatus(status)
        }
    }

    private func loadString(account: String) throws -> String? {
        if useInMemoryStore {
            return memoryStore[account]
        }
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: AnyObject?
        let status = keychain.copyMatching(query as CFDictionary, result: &item)
        switch status {
        case errSecSuccess:
            guard let encryptedData = item as? Data else {
                throw KeychainError.invalidData
            }
            let decryptedData = try decrypt(encryptedData)
            guard let string = String(data: decryptedData, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw mapStatus(status)
        }
    }

    private func deleteItem(account: String) throws {
        if useInMemoryStore {
            memoryStore.removeValue(forKey: account)
            return
        }
        let query = baseQuery(account: account)
        let status = keychain.delete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw mapStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        #if os(iOS)
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        #endif
        return query
    }

    private func mapStatus(_ status: OSStatus) -> KeychainError {
        switch status {
        case errSecItemNotFound:
            return .itemNotFound
        case errSecDuplicateItem:
            return .duplicateItem
        default:
            return .unexpectedStatus(status)
        }
    }

    private func encrypt(_ data: Data) throws -> Data {
        if useInMemoryStore {
            return data
        }
        let key = try loadOrCreateEncryptionKey()
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                throw KeychainError.invalidData
            }
            return combined
        } catch {
            throw KeychainError.invalidData
        }
    }

    private func decrypt(_ data: Data) throws -> Data {
        if useInMemoryStore {
            return data
        }
        let key = try loadOrCreateEncryptionKey()
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw KeychainError.invalidData
        }
    }

    private func loadOrCreateEncryptionKey() throws -> SymmetricKey {
        if let cachedEncryptionKey {
            return cachedEncryptionKey
        }
        if let storedKeyData = try loadRawData(account: encryptionKeyAccount) {
            let key = SymmetricKey(data: storedKeyData)
            cachedEncryptionKey = key
            return key
        }
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try saveRawData(keyData, account: encryptionKeyAccount)
        cachedEncryptionKey = key
        return key
    }

    private func loadRawData(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: AnyObject?
        let status = keychain.copyMatching(query as CFDictionary, result: &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainError.invalidData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw mapStatus(status)
        }
    }

    private func saveRawData(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        var attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        #if os(iOS)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #endif
        attributes[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any

        let status = keychain.update(query as CFDictionary, attributes: attributes as CFDictionary)
        if status == errSecItemNotFound {
            var create = query
            create[kSecValueData as String] = data
            #if os(iOS)
            create[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            #endif
            create[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
            let addStatus = keychain.add(create as CFDictionary, result: nil)
            if addStatus != errSecSuccess {
                throw mapStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw mapStatus(status)
        }
    }
}
