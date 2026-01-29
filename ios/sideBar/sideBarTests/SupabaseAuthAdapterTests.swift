import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SupabaseAuthAdapterTests: XCTestCase {
    private let lastAuthTimestampKey = AppStorageKeys.lastAuthTimestamp

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: lastAuthTimestampKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: lastAuthTimestampKey)
        super.tearDown()
    }

    func testJwtExpiryDateUsesExpClaim() {
        let exp: TimeInterval = 1_800_000_000
        let header = base64UrlEncode(["alg": "none", "typ": "JWT"])
        let payload = base64UrlEncode(["exp": exp, "sub": "user"])
        let token = "\(header).\(payload)."

        let date = SupabaseAuthAdapter.jwtExpiryDate(from: token)
        XCTAssertEqual(date, Date(timeIntervalSince1970: exp))
    }

    func testJwtExpiryDateReturnsNilForInvalidToken() {
        let date = SupabaseAuthAdapter.jwtExpiryDate(from: "invalid-token")
        XCTAssertNil(date)
    }

    func testOfflineAccessAllowsStoredCredentialsWithinWindow() {
        let store = InMemoryAuthStateStore()
        try? store.saveAccessToken("token")
        try? store.saveUserId("user")
        let withinWindow = Date().addingTimeInterval(-12 * 60 * 60)
        UserDefaults.standard.set(withinWindow.timeIntervalSince1970, forKey: lastAuthTimestampKey)

        let adapter = SupabaseAuthAdapter(
            config: EnvironmentConfig.fallbackForTesting(),
            stateStore: store
        )

        XCTAssertEqual(adapter.accessToken, "token")
        XCTAssertEqual(adapter.userId, "user")
    }

    func testOfflineAccessRejectsStoredCredentialsOutsideWindow() {
        let store = InMemoryAuthStateStore()
        try? store.saveAccessToken("token")
        try? store.saveUserId("user")
        let outsideWindow = Date().addingTimeInterval(-48 * 60 * 60)
        UserDefaults.standard.set(outsideWindow.timeIntervalSince1970, forKey: lastAuthTimestampKey)

        let adapter = SupabaseAuthAdapter(
            config: EnvironmentConfig.fallbackForTesting(),
            stateStore: store
        )

        XCTAssertNil(adapter.accessToken)
        XCTAssertNil(adapter.userId)
    }

    private func base64UrlEncode(_ payload: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [])
        let encoded = data?.base64EncodedString() ?? ""
        return encoded
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
