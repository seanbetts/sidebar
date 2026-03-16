import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelSessionScopeSaveTests: XCTestCase {
    func testSaveUserSettingsUsesLoadedCurrentUserSettingsWithoutAuthorizedSessionPreflight() async {
        let loaded = UserSettings(
            userId: "user-2",
            communicationStyle: "Concise",
            workingRelationship: "Direct",
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
        let updated = UserSettings(
            userId: "user-2",
            communicationStyle: "Detailed",
            workingRelationship: "Direct",
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
        let api = SessionScopeSaveSettingsAPI(
            getSettings: {
                XCTFail("Settings reload should not run when the loaded settings already match the current user.")
                return loaded
            },
            updateSettings: { _ in
                updated
            }
        )
        var refreshCallCount = 0
        let viewModel = SettingsViewModel(
            settingsAPI: api,
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: TestCacheClient(),
            currentAuthUserIdProvider: { "user-2" },
            currentAuthorizedUserIdProvider: { nil },
            refreshAuthorizedSession: {
                refreshCallCount += 1
            }
        )

        viewModel.applySettingsResponse(loaded)
        await viewModel.saveUserSettings(
            communicationStyle: "Detailed",
            workingRelationship: "Direct"
        )

        XCTAssertEqual(refreshCallCount, 0)
        XCTAssertEqual(api.getSettingsCallCount, 0)
        XCTAssertEqual(api.updateSettingsCallCount, 1)
        XCTAssertEqual(viewModel.settings?.communicationStyle, "Detailed")
        XCTAssertNil(viewModel.systemSaveError)
        XCTAssertEqual(viewModel.settingsSaveCompletionCount, 1)
    }

    func testSaveUserSettingsMapsUpdateAuthFailureIntoSessionExpiredMessage() async {
        let loaded = UserSettings(
            userId: "user-2",
            communicationStyle: "Concise",
            workingRelationship: "Direct",
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
        let api = SessionScopeSaveSettingsAPI(
            getSettings: {
                loaded
            },
            updateSettings: { _ in
                throw APIClientError.requestFailed(401)
            }
        )
        let viewModel = SettingsViewModel(
            settingsAPI: api,
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: TestCacheClient(),
            currentAuthUserIdProvider: { "user-2" }
        )

        viewModel.applySettingsResponse(loaded)
        await viewModel.saveUserSettings(
            communicationStyle: "Detailed",
            workingRelationship: "Direct"
        )

        XCTAssertEqual(api.getSettingsCallCount, 0)
        XCTAssertEqual(api.updateSettingsCallCount, 1)
        XCTAssertEqual(viewModel.systemSaveError, "Session expired. Please sign in again.")
        XCTAssertEqual(viewModel.settingsSaveCompletionCount, 0)
    }
}

@MainActor
private final class SessionScopeSaveSettingsAPI: SettingsProviding {
    private let getSettingsHandler: () throws -> UserSettings
    private let updateSettingsHandler: (SettingsUpdate) throws -> UserSettings

    private(set) var getSettingsCallCount: Int = 0
    private(set) var updateSettingsCallCount: Int = 0

    init(
        getSettings: @escaping () throws -> UserSettings,
        updateSettings: @escaping (SettingsUpdate) throws -> UserSettings
    ) {
        self.getSettingsHandler = getSettings
        self.updateSettingsHandler = updateSettings
    }

    func getSettings() async throws -> UserSettings {
        getSettingsCallCount += 1
        return try getSettingsHandler()
    }

    func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        throw SettingsViewModelMockError.forced
    }

    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        throw SettingsViewModelMockError.forced
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        updateSettingsCallCount += 1
        return try updateSettingsHandler(update)
    }

    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        throw SettingsViewModelMockError.forced
    }

    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        _ = provider
        _ = apiKey
        throw SettingsViewModelMockError.forced
    }

    func deleteProviderKey(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        throw SettingsViewModelMockError.forced
    }

    func getProfileImage() async throws -> Data {
        throw SettingsViewModelMockError.forced
    }

    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        _ = data
        _ = contentType
        _ = filename
    }

    func deleteProfileImage() async throws {
    }
}
