import XCTest
import Security
@testable import sideBar

final class KeychainAuthStateStoreTests: XCTestCase {
    private static var retainedStores: [KeychainAuthStateStore] = []

    private final class TestKeychainClient: KeychainClient {
        var storage: [String: Data] = [:]
        var nextCopyStatus: OSStatus?
        var nextUpdateStatus: OSStatus?
        var nextAddStatus: OSStatus?
        var nextDeleteStatus: OSStatus?

        func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
            if let status = nextCopyStatus {
                nextCopyStatus = nil
                return status
            }
            guard let account = (query as NSDictionary)[kSecAttrAccount as String] as? String else {
                return errSecParam
            }
            guard let data = storage[account] else {
                return errSecItemNotFound
            }
            result?.pointee = data as AnyObject
            return errSecSuccess
        }

        func add(_ attributes: CFDictionary, result: UnsafeMutablePointer<AnyObject?>?) -> OSStatus {
            if let status = nextAddStatus {
                nextAddStatus = nil
                return status
            }
            guard let account = (attributes as NSDictionary)[kSecAttrAccount as String] as? String else {
                return errSecParam
            }
            if storage[account] != nil {
                return errSecDuplicateItem
            }
            guard let data = (attributes as NSDictionary)[kSecValueData as String] as? Data else {
                return errSecParam
            }
            storage[account] = data
            return errSecSuccess
        }

        func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
            if let status = nextUpdateStatus {
                nextUpdateStatus = nil
                return status
            }
            guard let account = (query as NSDictionary)[kSecAttrAccount as String] as? String else {
                return errSecParam
            }
            guard storage[account] != nil else {
                return errSecItemNotFound
            }
            guard let data = (attributes as NSDictionary)[kSecValueData as String] as? Data else {
                return errSecParam
            }
            storage[account] = data
            return errSecSuccess
        }

        func delete(_ query: CFDictionary) -> OSStatus {
            if let status = nextDeleteStatus {
                nextDeleteStatus = nil
                return status
            }
            guard let account = (query as NSDictionary)[kSecAttrAccount as String] as? String else {
                return errSecParam
            }
            if storage.removeValue(forKey: account) != nil {
                return errSecSuccess
            }
            return errSecItemNotFound
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
}
