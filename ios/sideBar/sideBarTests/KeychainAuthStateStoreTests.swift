import XCTest
import sideBarShared
import Security
import CryptoKit
@testable import sideBar

final class KeychainAuthStateStoreTests: XCTestCase {
    private static var retainedStores: [KeychainAuthStateStore] = []

    private final class TestKeychainClient: KeychainClient {
        var storage: [String: Data] = [:]
        var legacyStorage: [String: Data] = [:]
        var dataProtectionStorage: [String: Data] = [:]
        var nextCopyStatus: OSStatus?
        var nextUpdateStatus: OSStatus?
        var nextAddStatus: OSStatus?
        var nextDeleteStatus: OSStatus?
        var lastUpdateQuery: NSDictionary?
        var lastAddAttributes: NSDictionary?
        var lastCopyQuery: NSDictionary?
        var deleteQueries: [NSDictionary] = []

        func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
            lastCopyQuery = query as NSDictionary
            if let status = nextCopyStatus {
                nextCopyStatus = nil
                return status
            }
            guard let account = (query as NSDictionary)[kSecAttrAccount as String] as? String else {
                return errSecParam
            }
            guard let data = storageForQuery(query as NSDictionary)[account] else {
                return errSecItemNotFound
            }
            result?.pointee = data as AnyObject
            return errSecSuccess
        }

        func add(_ attributes: CFDictionary, result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
            lastAddAttributes = attributes as NSDictionary
            if let status = nextAddStatus {
                nextAddStatus = nil
                return status
            }
            guard let account = (attributes as NSDictionary)[kSecAttrAccount as String] as? String else {
                return errSecParam
            }
            var storage = storageForQuery(attributes as NSDictionary)
            if storage[account] != nil {
                return errSecDuplicateItem
            }
            guard let data = (attributes as NSDictionary)[kSecValueData as String] as? Data else {
                return errSecParam
            }
            storage[account] = data
            setStorage(storage, for: attributes as NSDictionary)
            return errSecSuccess
        }

        func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
            lastUpdateQuery = query as NSDictionary
            if let status = nextUpdateStatus {
                nextUpdateStatus = nil
                return status
            }
            guard let account = (query as NSDictionary)[kSecAttrAccount as String] as? String else {
                return errSecParam
            }
            var storage = storageForQuery(query as NSDictionary)
            guard storage[account] != nil else {
                return errSecItemNotFound
            }
            guard let data = (attributes as NSDictionary)[kSecValueData as String] as? Data else {
                return errSecParam
            }
            storage[account] = data
            setStorage(storage, for: query as NSDictionary)
            return errSecSuccess
        }

        func delete(_ query: CFDictionary) -> OSStatus {
            deleteQueries.append(query as NSDictionary)
            if let status = nextDeleteStatus {
                nextDeleteStatus = nil
                return status
            }
            guard let account = (query as NSDictionary)[kSecAttrAccount as String] as? String else {
                return errSecParam
            }
            var storage = storageForQuery(query as NSDictionary)
            if storage.removeValue(forKey: account) != nil {
                setStorage(storage, for: query as NSDictionary)
                return errSecSuccess
            }
            return errSecItemNotFound
        }

        private func storageForQuery(_ query: NSDictionary) -> [String: Data] {
            if isDataProtectionQuery(query) {
                return dataProtectionStorage
            }
            if legacyStorage.isEmpty && dataProtectionStorage.isEmpty {
                return storage
            }
            return legacyStorage
        }

        private func setStorage(_ storage: [String: Data], for query: NSDictionary) {
            if isDataProtectionQuery(query) {
                dataProtectionStorage = storage
            } else if legacyStorage.isEmpty && dataProtectionStorage.isEmpty {
                self.storage = storage
            } else {
                legacyStorage = storage
            }
        }

        private func isDataProtectionQuery(_ query: NSDictionary) -> Bool {
            (query[kSecUseDataProtectionKeychain as String] as? Bool) == true
        }
    }

    func testSaveLoadAndClear() throws {
        let service = "sideBar.AuthTests.\(UUID().uuidString)"
        let store = KeychainAuthStateStore(service: service)
        Self.retainedStores.append(store)

        XCTAssertNoThrow(try store.saveAccessToken("token-123"))
        XCTAssertNoThrow(try store.saveUserId("user-456"))

        XCTAssertEqual(try store.loadAccessToken(), "token-123")
        XCTAssertEqual(try store.loadUserId(), "user-456")

        XCTAssertNoThrow(try store.clear())

        XCTAssertNil(try store.loadAccessToken())
        XCTAssertNil(try store.loadUserId())
    }

    func testNilSaveRemoves() throws {
        let service = "sideBar.AuthTests.\(UUID().uuidString)"
        let store = KeychainAuthStateStore(service: service)
        Self.retainedStores.append(store)

        XCTAssertNoThrow(try store.saveAccessToken("token-123"))
        XCTAssertEqual(try store.loadAccessToken(), "token-123")

        XCTAssertNoThrow(try store.saveAccessToken(nil))
        XCTAssertNil(try store.loadAccessToken())
    }

    func testLoadFailureInvalidData() {
        let client = TestKeychainClient()
        let store = KeychainAuthStateStore(
            service: "sideBar.AuthTests.\(UUID().uuidString)",
            keychain: client,
            useInMemoryStore: false
        )
        Self.retainedStores.append(store)
        client.storage["accessToken"] = Data([0x00, 0x01, 0x02])

        XCTAssertThrowsError(try store.loadAccessToken()) { error in
            XCTAssertEqual(error as? KeychainError, .invalidData)
        }
    }

    func testSaveFailureDuplicateItem() {
        let client = TestKeychainClient()
        client.storage["authEncryptionKey"] = Data(repeating: 0x1A, count: 32)
        client.nextUpdateStatus = errSecItemNotFound
        client.nextAddStatus = errSecDuplicateItem
        let store = KeychainAuthStateStore(
            service: "sideBar.AuthTests.\(UUID().uuidString)",
            keychain: client,
            useInMemoryStore: false
        )
        Self.retainedStores.append(store)

        XCTAssertThrowsError(try store.saveAccessToken("token-123")) { error in
            XCTAssertEqual(error as? KeychainError, .duplicateItem)
        }
    }

    func testInMemorySessionDataRoundTripAndRemove() throws {
        let store = KeychainAuthStateStore(
            service: "sideBar.AuthTests.\(UUID().uuidString)",
            useInMemoryStore: true
        )
        Self.retainedStores.append(store)
        let key = "supabase.session"
        let payload = Data("session-payload".utf8)

        try store.saveSessionData(payload, forKey: key)
        XCTAssertEqual(try store.loadSessionData(forKey: key), payload)

        try store.removeSessionData(forKey: key)
        XCTAssertNil(try store.loadSessionData(forKey: key))
    }

    func testSaveIncludesProvidedAccessGroupInKeychainQuery() throws {
        let client = TestKeychainClient()
        client.storage["authEncryptionKey"] = Data(repeating: 0x2A, count: 32)
        client.nextUpdateStatus = errSecItemNotFound
        let accessGroup = "TEAMID.ai.sidebar.sidebar"
        let store = KeychainAuthStateStore(
            service: "sideBar.AuthTests.\(UUID().uuidString)",
            accessGroup: accessGroup,
            keychain: client,
            useInMemoryStore: false
        )
        Self.retainedStores.append(store)

        try store.saveAccessToken("token-123")

        let updateAccessGroup = keychainStringValue(client.lastUpdateQuery, for: kSecAttrAccessGroup)
        let addAccessGroup = keychainStringValue(client.lastAddAttributes, for: kSecAttrAccessGroup)

        XCTAssertEqual(
            updateAccessGroup,
            accessGroup,
            "update query=\(String(describing: client.lastUpdateQuery))"
        )
        XCTAssertEqual(
            addAccessGroup,
            accessGroup,
            "add attrs=\(String(describing: client.lastAddAttributes))"
        )
    }

    #if os(macOS)
    func testSaveUsesDataProtectionKeychainOnMacOS() throws {
        let client = TestKeychainClient()
        client.dataProtectionStorage["authEncryptionKey"] = Data(repeating: 0x3B, count: 32)
        client.nextUpdateStatus = errSecItemNotFound
        let store = KeychainAuthStateStore(
            service: "sideBar.AuthTests.\(UUID().uuidString)",
            keychain: client,
            useInMemoryStore: false
        )
        Self.retainedStores.append(store)

        try store.saveAccessToken("token-123")

        XCTAssertEqual(
            client.lastUpdateQuery?[kSecUseDataProtectionKeychain as String] as? Bool,
            true,
            "update query=\(String(describing: client.lastUpdateQuery))"
        )
        XCTAssertEqual(
            client.lastAddAttributes?[kSecUseDataProtectionKeychain as String] as? Bool,
            true,
            "add attrs=\(String(describing: client.lastAddAttributes))"
        )
    }

    func testLoadMigratesLegacyMacOSItemsIntoDataProtectionKeychain() throws {
        let client = TestKeychainClient()
        let keyData = Data(repeating: 0x4C, count: 32)
        let key = SymmetricKey(data: keyData)
        let sealedBox = try AES.GCM.seal(Data("legacy-token".utf8), using: key)
        client.legacyStorage["authEncryptionKey"] = keyData
        client.legacyStorage["accessToken"] = try XCTUnwrap(sealedBox.combined)

        let store = KeychainAuthStateStore(
            service: "sideBar.AuthTests.\(UUID().uuidString)",
            keychain: client,
            useInMemoryStore: false
        )
        Self.retainedStores.append(store)

        XCTAssertEqual(try store.loadAccessToken(), "legacy-token")
        XCTAssertNotNil(client.dataProtectionStorage["authEncryptionKey"])
        XCTAssertNotNil(client.dataProtectionStorage["accessToken"])
        XCTAssertNil(client.legacyStorage["authEncryptionKey"])
        XCTAssertNil(client.legacyStorage["accessToken"])
    }
    #endif

    private func keychainStringValue(_ dictionary: NSDictionary?, for key: CFString) -> String? {
        guard let dictionary else {
            return nil
        }
        if let value = dictionary[key as String] as? String {
            return value
        }
        if let value = dictionary[key] as? String {
            return value
        }
        return nil
    }
}
