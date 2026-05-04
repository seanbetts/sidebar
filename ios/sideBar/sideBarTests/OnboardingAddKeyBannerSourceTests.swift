import XCTest

final class OnboardingAddKeyBannerSourceTests: XCTestCase {
    func testBannerUsesSharedStatusChromeInsteadOfCustomBannerModifier() throws {
        let normalized = try onboardingAddKeyBannerSource()

        XCTAssertTrue(normalized.contains(".glassChrome(.statusPill)"))
        XCTAssertFalse(normalized.contains("OnboardingAddKeyBannerChromeModifier"))
    }

    func testSettingsButtonUsesSharedPillChromeInsteadOfCustomButtonModifier() throws {
        let normalized = try onboardingAddKeyBannerSource()

        XCTAssertTrue(normalized.contains(".glassChrome(.pill)"))
        XCTAssertFalse(normalized.contains("AddKeyBannerButtonChrome"))
    }

    private func onboardingAddKeyBannerSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
            .appendingPathComponent("Chat")
            .appendingPathComponent("OnboardingAddKeyBanner.swift")
        return try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
}
