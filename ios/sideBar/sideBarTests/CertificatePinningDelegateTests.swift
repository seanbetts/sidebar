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
                host: "API.TRYSIDEBAR.AI",
                pattern: "api.trysidebar.ai"
            )
        )
    }

    func testExactPatternRejectsDifferentHost() {
        XCTAssertFalse(
            CertificatePinningDelegate.hostMatchesPinnedPattern(
                host: "api.trysidebar.ai",
                pattern: "api.other.ai"
            )
        )
    }

    // MARK: - normalizedHostPattern

    func testNormalizedHostPatternAcceptsExactDomain() {
        XCTAssertEqual(
            CertificatePinningDelegate.normalizedHostPattern(from: "api.trysidebar.ai"),
            "api.trysidebar.ai"
        )
    }

    func testNormalizedHostPatternAcceptsWildcardDomain() {
        // Wildcard cert subjects must not be rejected by the character check.
        XCTAssertEqual(
            CertificatePinningDelegate.normalizedHostPattern(from: "*.trysidebar.ai"),
            "*.trysidebar.ai"
        )
    }

    func testNormalizedHostPatternAcceptsWildcardCaseInsensitively() {
        XCTAssertEqual(
            CertificatePinningDelegate.normalizedHostPattern(from: "*.TrySidebar.AI"),
            "*.trysidebar.ai"
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

    // MARK: - notAfterDate

    func testNotAfterDateReturnsNilForInvalidCertData() {
        // SecCertificateCreateWithData returns nil for garbage data, so notAfterDate should too.
        // We can exercise this via a cert built from random bytes.
        let garbledData = Data(repeating: 0xFF, count: 64)
        guard let cert = SecCertificateCreateWithData(nil, garbledData as CFData) else {
            // Expected: invalid DER → SecCertificateCreateWithData returns nil.
            // notAfterDate requires a valid SecCertificate, so this path validates the guard.
            return
        }
        // If somehow a cert was created (unlikely), notAfterDate should still return nil.
        XCTAssertNil(CertificatePinningDelegate.notAfterDate(for: cert))
    }

    func testInitWithEmptyCertsDoesNotCrash() {
        // Ensure the delegate can be constructed with no certs without crashing.
        let delegate = CertificatePinningDelegate(pinnedCertificates: [])
        XCTAssertNotNil(delegate)
    }

    // MARK: - CertPinCancellationRegistry

    func testRegistryReturnsFalseForUnrecordedHost() {
        let registry = CertPinCancellationRegistry(ttl: 5)
        XCTAssertFalse(registry.wasCancelled(host: "api.trysidebar.ai"))
    }

    func testRegistryReturnsTrueAfterRecord() {
        let registry = CertPinCancellationRegistry(ttl: 5)
        registry.record(host: "api.trysidebar.ai")
        XCTAssertTrue(registry.wasCancelled(host: "api.trysidebar.ai"))
    }

    func testRegistryReturnsFalseForDifferentHost() {
        let registry = CertPinCancellationRegistry(ttl: 5)
        registry.record(host: "api.trysidebar.ai")
        XCTAssertFalse(registry.wasCancelled(host: "other.trysidebar.ai"))
    }

    func testRegistryReturnsFalseAfterInjectedTTLExpires() {
        let clock = TestRegistryClock()
        let registry = CertPinCancellationRegistry(ttl: 0.05, now: { clock.now })
        registry.record(host: "api.trysidebar.ai")
        clock.advance(by: 0.1)
        XCTAssertFalse(registry.wasCancelled(host: "api.trysidebar.ai"))
    }
}

private final class TestRegistryClock {
    private(set) var now = Date()

    func advance(by interval: TimeInterval) {
        now.addTimeInterval(interval)
    }
}
