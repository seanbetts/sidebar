import XCTest

final class ChatOnboardingRecoverySourceTests: XCTestCase {
    func testChatViewIncludesProviderRecoveryBannerAndSettingsCTA() throws {
        let normalized = try combinedChatSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "ifenvironment.settingsViewModel.signedInOnboardingRecoveryState==.providerRecovery{OnboardingAddKeyBanner{environment.commandSelection=.settings}"
            )
        )
        XCTAssertTrue(normalized.contains(".frame(maxWidth:contentMaxWidth)"))
    }

    func testProviderRecoveryBannerUsesPersistentNoKeyCopy() throws {
        let normalized = try combinedChatSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("AddanAPIkeytostartusingtheassistant"))
        XCTAssertTrue(
            normalized.contains(
                "Notes,tasks,websites,andfilesstillworkwhilechatstaysunavailable."
            )
        )
        XCTAssertTrue(normalized.contains("OpenSettings"))
    }

    private func combinedChatSource(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let fileURL = URL(fileURLWithPath: "\(file)")
        let sideBarRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewsRoot = sideBarRoot
            .appendingPathComponent("sideBar")
            .appendingPathComponent("Views")
        let sourceURLs = [
            viewsRoot.appendingPathComponent("Chat").appendingPathComponent("ChatView.swift"),
            viewsRoot.appendingPathComponent("Chat").appendingPathComponent("OnboardingAddKeyBanner.swift")
        ]

        do {
            return try sourceURLs
                .map { try String(contentsOf: $0, encoding: .utf8) }
                .joined(separator: "\n")
        } catch {
            XCTFail("Failed to read chat onboarding recovery sources: \(error)", file: file, line: line)
            throw error
        }
    }
}
