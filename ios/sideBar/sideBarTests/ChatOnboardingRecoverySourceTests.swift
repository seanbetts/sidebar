import XCTest

final class ChatOnboardingRecoverySourceTests: XCTestCase {
    func testChatViewIncludesProviderRecoveryBannerAndSettingsCTA() throws {
        let normalized = try combinedChatSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let settingsRouteSource =
            "ifenvironment.settingsViewModel.signedInOnboardingRecoveryState==.providerRecovery{" +
            "OnboardingAddKeyBanner{" +
            "UserDefaults.standard.set(\"agent\",forKey:AppStorageKeys.settingsSelectedSection)" +
            "UserDefaults.standard.set(\"agent\",forKey:AppStorageKeys.settingsSelectedTab)" +
            "environment.commandSelection=.settings}"

        XCTAssertTrue(
            normalized.contains(settingsRouteSource)
        )
        XCTAssertTrue(normalized.contains(".frame(maxWidth:contentMaxWidth)"))
    }

    func testProviderRecoveryBannerUsesPersistentNoKeyCopy() throws {
        let normalized = try combinedChatSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("ChatneedsanAPIkey"))
        XCTAssertTrue(normalized.contains(".accessibilityLabel(\"OpenSettings\")"))
    }

    func testChatViewDoesNotSurfacePermissionRecoveryCards() throws {
        let normalized = try combinedChatSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertFalse(normalized.contains("signedInOnboardingRecoveryState==.permissionRecovery"))
        XCTAssertFalse(normalized.contains("permissionRecoveryItems"))
        XCTAssertFalse(normalized.contains("OnboardingPermissionCard(item:item)"))
    }

    func testChatViewSurfacesFeatureDiscoveryCarousel() throws {
        let normalized = try combinedChatSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "environment.settingsViewModel.signedInOnboardingRecoveryState==.featureDiscovery"
            )
        )
        XCTAssertTrue(normalized.contains("StaticFeatureCarousel"))
    }

    func testSelectingFeatureDiscoveryTileDoesNotDismissCarousel() throws {
        let normalized = try combinedChatSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("awaitviewModel.startFeatureDiscovery(for:feature)"))
        XCTAssertFalse(
            normalized.contains(
                "onSelectFeature:{featureinTask{awaitenvironment.settingsViewModel.markFeatureDiscoverySeen()"
            )
        )
    }

    func testSelectingFeatureDiscoveryTileCollapsesCarousel() throws {
        let normalized = try combinedChatSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "FeatureIntroCard(feature:feature){collapseExpandedContent()onSelectFeature(feature)}"
            )
        )
    }

    func testFeatureDiscoveryUsesExpandableGlassPresentation() throws {
        let normalized = try combinedChatSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(normalized.contains("GlassEffectContainer"))
        XCTAssertTrue(normalized.contains("ExploresideBar"))
        XCTAssertTrue(normalized.contains("Expandfeaturediscovery"))
        XCTAssertTrue(normalized.contains("Dismissfeaturediscovery"))
    }

    func testChatComposerIsDisabledDuringProviderRecovery() throws {
        let normalized = try combinedChatSource()
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        XCTAssertTrue(
            normalized.contains(
                "environment.settingsViewModel.signedInOnboardingRecoveryState!=.providerRecovery"
            )
        )
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
            viewsRoot.appendingPathComponent("Chat").appendingPathComponent("OnboardingAddKeyBanner.swift"),
            viewsRoot.appendingPathComponent("Chat").appendingPathComponent("StaticFeatureCarousel.swift"),
            viewsRoot.appendingPathComponent("Chat").appendingPathComponent("FeatureIntroCard.swift")
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
