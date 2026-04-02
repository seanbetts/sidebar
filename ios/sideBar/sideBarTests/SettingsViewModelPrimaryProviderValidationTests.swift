import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsProviderKeyValidationTests: XCTestCase {
    func testSavePrimaryProviderKeySurfacesInvalidKeyError() async {
        let api = PrimaryProviderSettingsAPI(
            initial: providerSettings(primaryProvider: "anthropic"),
            upsertError: APIClientError.apiError("Invalid provider API key")
        )
        let viewModel = SettingsViewModel(
            settingsAPI: api,
            skillsAPI: PrimaryProviderEmptySkillsAPI(),
            cache: TestCacheClient()
        )

        await viewModel.load()
        let success = await viewModel.savePrimaryProviderKey(
            provider: AIPrimaryProvider.anthropic,
            apiKey: "invalid-key"
        )

        XCTAssertFalse(success)
        XCTAssertEqual(
            viewModel.primaryProviderError,
            "That API key doesn't look valid for this provider."
        )
    }

    func testSavePrimaryProviderKeyUsesProviderKeyFallbackMessageForBareBadRequest() async {
        let api = PrimaryProviderSettingsAPI(
            initial: providerSettings(primaryProvider: "anthropic"),
            upsertError: APIClientError.requestFailed(400)
        )
        let viewModel = SettingsViewModel(
            settingsAPI: api,
            skillsAPI: PrimaryProviderEmptySkillsAPI(),
            cache: TestCacheClient()
        )

        await viewModel.load()
        let success = await viewModel.savePrimaryProviderKey(
            provider: AIPrimaryProvider.anthropic,
            apiKey: "sk-ant-definitely-not-real"
        )

        XCTAssertFalse(success)
        XCTAssertEqual(
            viewModel.primaryProviderError,
            "We couldn't verify that API key. Check it and try again."
        )
    }

    private func providerSettings(primaryProvider: String) -> UserSettings {
        UserSettings(
            userId: "user-1",
            communicationStyle: nil,
            workingRelationship: nil,
            name: nil,
            jobTitle: nil,
            employer: nil,
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: nil,
            profileImageUrl: nil,
            aiPrimaryProvider: primaryProvider,
            aiPrimaryProviderHasKey: false,
            aiPrimaryProviderKeyLast4: nil,
            enabledSkills: []
        )
    }
}
