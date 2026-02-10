import Foundation
import XCTest
@testable import ShareExtension

final class ShareExtensionAuthRefresherTests: XCTestCase {
    func testShouldRefreshAccessTokenReturnsTrueWhenTokenExpiringSoon() {
        let now = Date(timeIntervalSince1970: 1_000)
        let expiringSoon = makeJWT(exp: 1_120)

        let shouldRefresh = ShareExtensionAuthRefresher.shouldRefreshAccessToken(
            expiringSoon,
            now: now,
            leadTime: 300
        )

        XCTAssertTrue(shouldRefresh)
    }

    func testShouldRefreshAccessTokenReturnsFalseWhenTokenHasPlentyOfTime() {
        let now = Date(timeIntervalSince1970: 1_000)
        let healthy = makeJWT(exp: 2_000)

        let shouldRefresh = ShareExtensionAuthRefresher.shouldRefreshAccessToken(
            healthy,
            now: now,
            leadTime: 300
        )

        XCTAssertFalse(shouldRefresh)
    }

    func testShouldRefreshAccessTokenReturnsTrueWhenTokenCannotBeDecoded() {
        let shouldRefresh = ShareExtensionAuthRefresher.shouldRefreshAccessToken(
            "invalid-token",
            now: Date(timeIntervalSince1970: 1_000),
            leadTime: 300
        )

        XCTAssertTrue(shouldRefresh)
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
