import XCTest
@testable import sideBarShared

final class CertificatePinningDelegateTests: XCTestCase {
    // MARK: - hostMatchesPinnedPattern

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

    // MARK: - normalizedHostPattern

    func testNormalizedHostPatternAcceptsExactDomain() {
        XCTAssertEqual(
            CertificatePinningDelegate.normalizedHostPattern(from: "api.sidebar.ai"),
            "api.sidebar.ai"
        )
    }

    func testNormalizedHostPatternAcceptsWildcardDomain() {
        // Wildcard cert subjects must not be rejected by the character check.
        XCTAssertEqual(
            CertificatePinningDelegate.normalizedHostPattern(from: "*.sidebar.ai"),
            "*.sidebar.ai"
        )
    }

    func testNormalizedHostPatternAcceptsWildcardCaseInsensitively() {
        XCTAssertEqual(
            CertificatePinningDelegate.normalizedHostPattern(from: "*.Sidebar.AI"),
            "*.sidebar.ai"
        )
    }

    func testNormalizedHostPatternRejectsNoDotBase() {
        XCTAssertNil(CertificatePinningDelegate.normalizedHostPattern(from: "localhost"))
        XCTAssertNil(CertificatePinningDelegate.normalizedHostPattern(from: "*.localhost"))
    }

    func testNormalizedHostPatternRejectsInvalidCharsInBase() {
        // Space in base domain is invalid.
        XCTAssertNil(CertificatePinningDelegate.normalizedHostPattern(from: "*.sidebar app.ai"))
        XCTAssertNil(CertificatePinningDelegate.normalizedHostPattern(from: "side bar.ai"))
    }

    func testNormalizedHostPatternRejectsEmbeddedWildcard() {
        // Wildcard not as a leading prefix is invalid.
        XCTAssertNil(CertificatePinningDelegate.normalizedHostPattern(from: "api.side*bar.ai"))
    }

    func testNormalizedHostPatternRejectsEmpty() {
        XCTAssertNil(CertificatePinningDelegate.normalizedHostPattern(from: ""))
        XCTAssertNil(CertificatePinningDelegate.normalizedHostPattern(from: "   "))
    }
}
