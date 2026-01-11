import Foundation
import Combine
import Security

public final class KeychainAuthStateStore: AuthStateStore {
    private let service: String
    private let accessTokenAccount = "accessToken"
    private let userIdAccount = "userId"
    private let useInMemoryStore: Bool
    private var memoryStore: [String: String] = [:]

    public init(service: String? = nil) {
        self.service = service ?? (Bundle.main.bundleIdentifier ?? "sideBar.Auth")
        self.useInMemoryStore = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    public func saveAccessToken(_ token: String?) {
        saveString(token, account: accessTokenAccount)
    }

    public func saveUserId(_ userId: String?) {
        saveString(userId, account: userIdAccount)
    }

    public func loadAccessToken() -> String? {
        loadString(account: accessTokenAccount)
    }

    public func loadUserId() -> String? {
        loadString(account: userIdAccount)
    }

    public func clear() {
        deleteItem(account: accessTokenAccount)
        deleteItem(account: userIdAccount)
    }

    private func saveString(_ value: String?, account: String) {
        if useInMemoryStore {
            if let value {
                memoryStore[account] = value
            } else {
                memoryStore.removeValue(forKey: account)
            }
            return
        }
        guard let value else {
            deleteItem(account: account)
            return
        }
        guard let data = value.data(using: .utf8) else {
            return
        }

        let query = baseQuery(account: account)
        var attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        #if os(iOS)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        #endif

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var create = query
            create[kSecValueData as String] = data
            #if os(iOS)
            create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            #endif
            _ = SecItemAdd(create as CFDictionary, nil)
        }
    }

    private func loadString(account: String) -> String? {
        if useInMemoryStore {
            return memoryStore[account]
        }
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func deleteItem(account: String) {
        if useInMemoryStore {
            memoryStore.removeValue(forKey: account)
            return
        }
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
