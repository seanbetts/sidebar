import XCTest
@testable import sideBar

final class SupabaseAuthAdapterTests: XCTestCase {
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

    private func base64UrlEncode(_ payload: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [])
        let encoded = data?.base64EncodedString() ?? ""
        return encoded
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
