import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelStoreInstallTests: XCTestCase {
    func testProviderKeyStatusUsesPrimaryProviderStatusWithoutNetworkCall() async throws {
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
            aiPrimaryProviderKeyLast4: "abcd",
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
        let status = try await viewModel.providerKeyStatus(provider: "  anthropic ")

        XCTAssertTrue(status.hasKey)
        XCTAssertEqual(status.provider, "anthropic")
        XCTAssertEqual(status.keyLast4, "abcd")
        XCTAssertEqual(providerRecorder.statusCallCount, 0)
    }

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

    func testSaveProviderKeyNormalizesProviderAndRefreshesSettings() async throws {
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
        let readRecorder = SettingsReadRecorder()
        let providerRecorder = ProviderKeyRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(settings),
                readRecorder: readRecorder,
                providerKeyRecorder: providerRecorder
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: TestCacheClient()
        )

        await viewModel.load()
        _ = try await viewModel.saveProviderKey(
            provider: "  OpenAI ",
            apiKey: " sk-openai-key "
        )

        XCTAssertEqual(providerRecorder.upsertCallCount, 1)
        XCTAssertEqual(providerRecorder.lastUpsertProvider, "openai")
        XCTAssertEqual(providerRecorder.lastUpsertApiKey, "sk-openai-key")
        XCTAssertEqual(readRecorder.getSettingsCallCount, 2)
    }

    func testDeleteProviderKeyNormalizesProviderAndRefreshesSettings() async throws {
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
        let readRecorder = SettingsReadRecorder()
        let providerRecorder = ProviderKeyRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(settings),
                readRecorder: readRecorder,
                providerKeyRecorder: providerRecorder
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: TestCacheClient()
        )

        await viewModel.load()
        _ = try await viewModel.deleteProviderKey(provider: "  Google ")

        XCTAssertEqual(providerRecorder.deleteCallCount, 1)
        XCTAssertEqual(providerRecorder.lastDeleteProvider, "google")
        XCTAssertEqual(readRecorder.getSettingsCallCount, 2)
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

    func testUninstallStoreSkillForwardsSkillIDToSkillsAPI() async {
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
        let uninstallRecorder = SkillsUninstallRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .success(settings)),
            skillsAPI: MockSkillsAPI(
                result: .success(SkillsResponse(skills: [])),
                uninstallResult: .success(
                    StoreSkillInstallResponse(
                        skillId: "planner",
                        installed: false,
                        enabled: false,
                        enabledSkills: [],
                        installedStoreSkills: []
                    )
                ),
                uninstallRecorder: uninstallRecorder
            ),
            cache: TestCacheClient()
        )
        await viewModel.load()

        let succeeded = await viewModel.uninstallStoreSkill(id: "planner")

        XCTAssertTrue(succeeded)
        XCTAssertEqual(uninstallRecorder.callCount, 1)
        XCTAssertEqual(uninstallRecorder.lastSkillId, "planner")
    }

    func testUninstallStoreSkillSetsErrorAndReturnsFalseOnFailure() async {
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
                uninstallResult: .failure(SettingsViewModelMockError.forced)
            ),
            cache: TestCacheClient()
        )
        await viewModel.load()

        let succeeded = await viewModel.uninstallStoreSkill(id: "planner")

        XCTAssertFalse(succeeded)
        XCTAssertNotNil(viewModel.skillsError)
    }
}
