import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelStoreInstallTests: XCTestCase {
    func testProviderHasKeyUsesPrimaryProviderStatusWithoutNetworkCall() async throws {
        let settings = UserSettings(
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
            aiPrimaryProvider: "anthropic",
            aiPrimaryProviderHasKey: true,
            enabledSkills: []
        )
        let providerRecorder = ProviderKeyRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(settings),
                providerKeyRecorder: providerRecorder
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: TestCacheClient()
        )

        await viewModel.load()
        let hasKey = try await viewModel.providerHasKey(provider: "  Anthropic ")

        XCTAssertTrue(hasKey)
        XCTAssertEqual(providerRecorder.statusCallCount, 0)
    }

    func testProviderHasKeyFetchesStatusForNonPrimaryProvider() async throws {
        let settings = UserSettings(
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
            aiPrimaryProvider: "anthropic",
            aiPrimaryProviderHasKey: true,
            enabledSkills: []
        )
        let providerRecorder = ProviderKeyRecorder()
        providerRecorder.statusByProvider["google"] = true
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(settings),
                providerKeyRecorder: providerRecorder
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: TestCacheClient()
        )

        await viewModel.load()
        let hasKey = try await viewModel.providerHasKey(provider: " Google ")

        XCTAssertTrue(hasKey)
        XCTAssertEqual(providerRecorder.statusCallCount, 1)
        XCTAssertEqual(providerRecorder.lastStatusProvider, "google")
    }

    func testInstallStoreSkillForwardsProviderKeysToSkillsAPI() async {
        let settings = UserSettings(
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
            enabledSkills: []
        )
        let installRecorder = SkillsInstallRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .success(settings)),
            skillsAPI: MockSkillsAPI(
                result: .success(SkillsResponse(skills: [])),
                installResult: .success(
                    StoreSkillInstallResponse(
                        skillId: "planner",
                        installed: true,
                        enabled: true,
                        enabledSkills: ["planner"],
                        installedStoreSkills: ["planner"]
                    )
                ),
                installRecorder: installRecorder
            ),
            cache: TestCacheClient()
        )
        await viewModel.load()

        let succeeded = await viewModel.installStoreSkill(
            id: "planner",
            providerKeys: [
                StoreSkillProviderKeyInput(provider: "openai", apiKey: "sk-openai"),
                StoreSkillProviderKeyInput(provider: "google", apiKey: "sk-google")
            ]
        )

        XCTAssertTrue(succeeded)
        XCTAssertEqual(installRecorder.callCount, 1)
        XCTAssertEqual(installRecorder.lastSkillId, "planner")
        XCTAssertEqual(
            installRecorder.lastProviderKeys?.map(\.provider),
            ["openai", "google"]
        )
        XCTAssertEqual(
            installRecorder.lastProviderKeys?.map(\.apiKey),
            ["sk-openai", "sk-google"]
        )
    }

    func testInstallStoreSkillSetsErrorAndReturnsFalseOnFailure() async {
        let settings = UserSettings(
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
            enabledSkills: []
        )
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .success(settings)),
            skillsAPI: MockSkillsAPI(
                result: .success(SkillsResponse(skills: [])),
                installResult: .failure(SettingsViewModelMockError.forced)
            ),
            cache: TestCacheClient()
        )
        await viewModel.load()

        let succeeded = await viewModel.installStoreSkill(id: "planner")

        XCTAssertFalse(succeeded)
        XCTAssertNotNil(viewModel.skillsError)
    }
}
