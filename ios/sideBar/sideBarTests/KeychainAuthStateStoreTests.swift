import XCTest
@testable import sideBar

final class KeychainAuthStateStoreTests: XCTestCase {
    func testSaveLoadAndClear() {
        let service = "sideBar.AuthTests.\(UUID().uuidString)"
        let store = KeychainAuthStateStore(service: service)

        store.saveAccessToken("token-123")
        store.saveUserId("user-456")

        XCTAssertEqual(store.loadAccessToken(), "token-123")
        XCTAssertEqual(store.loadUserId(), "user-456")

        store.clear()

        XCTAssertNil(store.loadAccessToken())
        XCTAssertNil(store.loadUserId())
    }

    func testNilSaveRemoves() {
        let service = "sideBar.AuthTests.\(UUID().uuidString)"
        let store = KeychainAuthStateStore(service: service)

        store.saveAccessToken("token-123")
        XCTAssertEqual(store.loadAccessToken(), "token-123")

        store.saveAccessToken(nil)
        XCTAssertNil(store.loadAccessToken())
    }
}
