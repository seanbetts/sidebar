import XCTest
import sideBarShared

final class CertificatePinningDelegateTests: XCTestCase {
    func testWildcardPatternMatchesSubdomain() {
        XCTAssertTrue(
            CertificatePinningDelegate.hostMatchesPinnedPattern(
                host: "api.fly.dev",
                pattern: "*.fly.dev"
            )
        )
    }

    func testWildcardPatternDoesNotMatchRootDomain() {
        XCTAssertFalse(
            CertificatePinningDelegate.hostMatchesPinnedPattern(
                host: "fly.dev",
                pattern: "*.fly.dev"
            )
        )
    }

    func testExactPatternMatchesHostCaseInsensitively() {
        XCTAssertTrue(
            CertificatePinningDelegate.hostMatchesPinnedPattern(
                host: "API.Sidebar.AI",
                pattern: "api.sidebar.ai"
            )
        )
    }

    func testExactPatternRejectsDifferentHost() {
        XCTAssertFalse(
            CertificatePinningDelegate.hostMatchesPinnedPattern(
                host: "api.sidebar.ai",
                pattern: "api.other.ai"
            )
        )
    }
}
