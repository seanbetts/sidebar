import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelSessionScopeTests: XCTestCase {
    func testSaveUserSettingsReloadsCurrentUserSettingsWhenLoadedSettingsBelongToDifferentAuthenticatedUser() async {
        let stale = UserSettings(
            userId: "user-1",
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
        let refreshed = UserSettings(
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
        let readRecorder = SettingsReadRecorder()
        let updateRecorder = UpdateRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(refreshed),
                updateResult: .success(updated),
                readRecorder: readRecorder,
                updateRecorder: updateRecorder
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: TestCacheClient(),
            currentAuthUserIdProvider: { "user-2" }
        )

        viewModel.applySettingsResponse(stale)
        await viewModel.saveUserSettings(
            communicationStyle: "Detailed",
            workingRelationship: "Direct"
        )

        XCTAssertEqual(readRecorder.getSettingsCallCount, 1)
        XCTAssertEqual(updateRecorder.callCount, 1)
        XCTAssertEqual(viewModel.settings?.userId, "user-2")
        XCTAssertEqual(viewModel.settings?.communicationStyle, "Detailed")
        XCTAssertEqual(viewModel.settingsSaveCompletionCount, 1)
        XCTAssertNil(viewModel.systemSaveError)
    }

    func testSaveUserSettingsSurfacesErrorWhenLoadedSettingsAndRefetchDoNotMatchAuthenticatedUser() async {
        let initial = UserSettings(
            userId: "user-1",
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
        let readRecorder = SettingsReadRecorder()
        let recorder = UpdateRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(initial),
                updateResult: .success(initial),
                readRecorder: readRecorder,
                updateRecorder: recorder
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: TestCacheClient(),
            currentAuthUserIdProvider: { "user-2" }
        )

        await viewModel.load()
        await viewModel.saveUserSettings(
            communicationStyle: "Detailed",
            workingRelationship: "Direct"
        )

        XCTAssertEqual(readRecorder.getSettingsCallCount, 2)
        XCTAssertEqual(recorder.callCount, 0)
        XCTAssertNotNil(viewModel.systemSaveError)
        XCTAssertEqual(viewModel.settingsSaveCompletionCount, 0)
    }

    func testSaveProfileSettingsReloadsCurrentUserSettingsWhenLoadedSettingsBelongToDifferentAuthenticatedUser() async {
        let stale = UserSettings(
            userId: "user-1",
            communicationStyle: nil,
            workingRelationship: nil,
            name: "Sam",
            jobTitle: "Founder",
            employer: "Old Co",
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: "Boston",
            profileImageUrl: nil,
            enabledSkills: []
        )
        let refreshed = UserSettings(
            userId: "user-2",
            communicationStyle: nil,
            workingRelationship: nil,
            name: "Sam",
            jobTitle: "Founder",
            employer: "Current Co",
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: "Seattle",
            profileImageUrl: nil,
            enabledSkills: []
        )
        let updated = UserSettings(
            userId: "user-2",
            communicationStyle: nil,
            workingRelationship: nil,
            name: "Sam",
            jobTitle: "Founder",
            employer: "Current Co",
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: "London",
            profileImageUrl: nil,
            enabledSkills: []
        )
        let readRecorder = SettingsReadRecorder()
        let updateRecorder = UpdateRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(refreshed),
                updateResult: .success(updated),
                readRecorder: readRecorder,
                updateRecorder: updateRecorder
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: TestCacheClient(),
            currentAuthUserIdProvider: { "user-2" }
        )

        viewModel.applySettingsResponse(stale)
        await viewModel.saveProfileSettings(
            name: "Sam",
            jobTitle: "Founder",
            employer: "Current Co",
            dateOfBirth: nil,
            dateOfBirthEnabled: false,
            gender: "",
            pronouns: "",
            location: "London"
        )

        XCTAssertEqual(readRecorder.getSettingsCallCount, 1)
        XCTAssertEqual(updateRecorder.callCount, 1)
        XCTAssertEqual(viewModel.settings?.userId, "user-2")
        XCTAssertEqual(viewModel.settings?.location, "London")
        XCTAssertEqual(viewModel.settingsSaveCompletionCount, 1)
        XCTAssertNil(viewModel.profileSaveError)
    }

    func testSaveUserSettingsSurfacesErrorWhenReloadedSettingsStillDoNotMatchAuthenticatedUser() async {
        let stale = UserSettings(
            userId: "user-1",
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
        let readRecorder = SettingsReadRecorder()
        let updateRecorder = UpdateRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(stale),
                updateResult: .success(stale),
                readRecorder: readRecorder,
                updateRecorder: updateRecorder
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: TestCacheClient(),
            currentAuthUserIdProvider: { "user-2" }
        )

        viewModel.applySettingsResponse(stale)
        await viewModel.saveUserSettings(
            communicationStyle: "Detailed",
            workingRelationship: "Direct"
        )

        XCTAssertEqual(readRecorder.getSettingsCallCount, 1)
        XCTAssertEqual(updateRecorder.callCount, 0)
        XCTAssertNotNil(viewModel.systemSaveError)
        XCTAssertEqual(viewModel.settingsSaveCompletionCount, 0)
    }

    func testSaveUserSettingsRefreshesAuthorizedSessionBeforeReloadingWhenAuthScopeExistsWithoutToken() async {
        let stale = UserSettings(
            userId: "user-1",
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
        let refreshed = UserSettings(
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
        var authorizedUserId: String?
        let api = SessionScopeSettingsAPI(
            getSettings: {
                authorizedUserId == nil ? stale : refreshed
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
            currentAuthorizedUserIdProvider: { authorizedUserId },
            refreshAuthorizedSession: {
                refreshCallCount += 1
                authorizedUserId = "user-2"
            }
        )

        viewModel.applySettingsResponse(stale)
        await viewModel.saveUserSettings(
            communicationStyle: "Detailed",
            workingRelationship: "Direct"
        )

        XCTAssertEqual(refreshCallCount, 1)
        XCTAssertEqual(api.getSettingsCallCount, 1)
        XCTAssertEqual(api.updateSettingsCallCount, 1)
        XCTAssertEqual(viewModel.settings?.userId, "user-2")
        XCTAssertEqual(viewModel.settings?.communicationStyle, "Detailed")
        XCTAssertNil(viewModel.systemSaveError)
        XCTAssertEqual(viewModel.settingsSaveCompletionCount, 1)
    }

    func testSaveUserSettingsSurfacesSessionExpiredWithoutReloadingWhenAuthorizedSessionCannotBeRecovered() async {
        let stale = UserSettings(
            userId: "user-1",
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
        let api = SessionScopeSettingsAPI(
            getSettings: {
                XCTFail("Settings reload should not run without an authorized session.")
                return stale
            },
            updateSettings: { _ in
                XCTFail("Settings update should not run without an authorized session.")
                return stale
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

        viewModel.applySettingsResponse(stale)
        await viewModel.saveUserSettings(
            communicationStyle: "Detailed",
            workingRelationship: "Direct"
        )

        XCTAssertEqual(refreshCallCount, 1)
        XCTAssertEqual(api.getSettingsCallCount, 0)
        XCTAssertEqual(api.updateSettingsCallCount, 0)
        XCTAssertEqual(viewModel.systemSaveError, "Session expired. Please sign in again.")
        XCTAssertEqual(viewModel.settings?.userId, "user-1")
        XCTAssertEqual(viewModel.settingsSaveCompletionCount, 0)
    }

    func testResetClearsLoadedSettingsState() async {
        let initial = UserSettings(
            userId: "user-1",
            communicationStyle: nil,
            workingRelationship: nil,
            name: "User",
            jobTitle: nil,
            employer: nil,
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: nil,
            profileImageUrl: "https://example.com/profile.png",
            enabledSkills: []
        )
        let profileImageData = Data([0x01, 0x02, 0x03])
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(initial),
                tokenResult: .success(ShortcutsTokenResponse(token: "shortcuts-token")),
                profileImageResult: .success(profileImageData)
            ),
            skillsAPI: MockSkillsAPI(
                result: .success(
                    SkillsResponse(skills: [
                        SkillItem(id: "s1", name: "Skill", description: "Desc", category: "General")
                    ])
                )
            ),
            cache: TestCacheClient()
        )

        await viewModel.load()
        await viewModel.loadSkills()
        await viewModel.loadShortcutsToken()
        await viewModel.loadProfileImage()

        XCTAssertNotNil(viewModel.settings)
        XCTAssertFalse(viewModel.skills.isEmpty)
        XCTAssertEqual(viewModel.shortcutsToken, "shortcuts-token")
        XCTAssertEqual(viewModel.profileImageData, profileImageData)

        viewModel.reset()

        XCTAssertNil(viewModel.settings)
        XCTAssertTrue(viewModel.skills.isEmpty)
        XCTAssertEqual(viewModel.shortcutsToken, "")
        XCTAssertNil(viewModel.profileImageData)
        XCTAssertNil(viewModel.profileSaveError)
        XCTAssertNil(viewModel.systemSaveError)
        XCTAssertNil(viewModel.skillsError)
        XCTAssertNil(viewModel.primaryProviderError)
    }
}

@MainActor
private final class SessionScopeSettingsAPI: SettingsProviding {
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
