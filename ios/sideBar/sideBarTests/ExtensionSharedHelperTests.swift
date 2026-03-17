import Foundation
import Supabase
import XCTest
import sideBarShared

final class ExtensionSharedHelperTests: XCTestCase {
    func testConfigNormalizationRejectsUnresolvedBuildSettingValues() {
        XCTAssertNil(ConfigNormalization.normalizeConfigValue("$(SUPABASE_URL)"))
        XCTAssertNil(ConfigNormalization.normalizeConfigValue("${SUPABASE_URL}"))
        XCTAssertEqual(
            ConfigNormalization.normalizeConfigValue(" https:\\/\\/api.example.com \n"),
            "https://api.example.com"
        )
    }

    func testConfigNormalizationParsesOnlyHTTPURLs() {
        XCTAssertEqual(
            ConfigNormalization.parseHTTPURL(from: "https://api.example.com")?.absoluteString,
            "https://api.example.com"
        )
        XCTAssertNil(ConfigNormalization.parseHTTPURL(from: "ftp://api.example.com"))
        XCTAssertNil(ConfigNormalization.parseHTTPURL(from: "https:///missing-host"))
    }

    func testJWTExpiryRefreshesExpiringTokensAndRejectsInvalidPayloads() {
        let now = Date(timeIntervalSince1970: 1_000)
        let expiringSoon = makeJWT(exp: 1_120)
        let healthy = makeJWT(exp: 2_000)

        XCTAssertTrue(JWTExpiry.shouldRefreshAccessToken(expiringSoon, now: now, leadTime: 300))
        XCTAssertFalse(JWTExpiry.shouldRefreshAccessToken(healthy, now: now, leadTime: 300))
        XCTAssertTrue(JWTExpiry.shouldRefreshAccessToken("invalid-token", now: now, leadTime: 300))
    }

    func testSupabaseKeychainStorageBridgeUsesSharedKeychainStore() throws {
        let store = KeychainAuthStateStore(
            service: "ExtensionSharedHelperTests",
            accessGroup: nil,
            useInMemoryStore: true
        )
        let bridge: AuthLocalStorage = SupabaseKeychainStorageBridge(stateStore: store)
        let payload = Data("session".utf8)

        try bridge.store(key: "supabase.auth.token", value: payload)
        XCTAssertEqual(try bridge.retrieve(key: "supabase.auth.token"), payload)

        try bridge.remove(key: "supabase.auth.token")
        XCTAssertNil(try bridge.retrieve(key: "supabase.auth.token"))
    }

    private func makeJWT(exp: TimeInterval) -> String {
        let header = #"{"alg":"HS256","typ":"JWT"}"#
        let payload = #"{"exp":\#(Int(exp))}"#
        return "\(base64URL(header)).\(base64URL(payload)).signature"
    }

    private func base64URL(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
