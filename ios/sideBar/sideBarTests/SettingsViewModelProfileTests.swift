import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelProfileTests: XCTestCase {
    func testSaveProfileSettingsSendsLocationUpdate() async throws {
        let initial = UserSettings(
            userId: "user-1",
            communicationStyle: nil,
            workingRelationship: nil,
            name: "Sam",
            jobTitle: nil,
            employer: nil,
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: "Boston",
            profileImageUrl: nil,
            enabledSkills: []
        )
        let updated = UserSettings(
            userId: "user-1",
            communicationStyle: nil,
            workingRelationship: nil,
            name: "Sam",
            jobTitle: nil,
            employer: nil,
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: "Seattle",
            profileImageUrl: nil,
            enabledSkills: []
        )
        let api = RecordingSettingsAPI(initial: initial, updated: updated)
        let viewModel = SettingsViewModel(
            settingsAPI: api,
            skillsAPI: EmptySkillsAPI(),
            cache: TestCacheClient()
        )

        await viewModel.load()
        await viewModel.saveProfileSettings(
            name: "Sam",
            jobTitle: "",
            employer: "",
            dateOfBirth: nil,
            dateOfBirthEnabled: false,
            gender: "",
            pronouns: "",
            location: "Seattle"
        )

        XCTAssertEqual(api.updateCallCount, 1)
        let payload = try encodedPayload(try XCTUnwrap(api.lastUpdate))
        XCTAssertEqual(payload["location"] as? String, "Seattle")
        XCTAssertEqual(viewModel.settings?.location, "Seattle")
    }

    func testSaveProfileSettingsClearingDateEncodesNullDate() async throws {
        let initial = UserSettings(
            userId: "user-1",
            communicationStyle: nil,
            workingRelationship: nil,
            name: "Sam",
            jobTitle: nil,
            employer: nil,
            dateOfBirth: "1990-04-12",
            gender: nil,
            pronouns: nil,
            location: nil,
            profileImageUrl: nil,
            enabledSkills: []
        )
        let updated = UserSettings(
            userId: "user-1",
            communicationStyle: nil,
            workingRelationship: nil,
            name: "Sam",
            jobTitle: nil,
            employer: nil,
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: nil,
            profileImageUrl: nil,
            enabledSkills: []
        )
        let api = RecordingSettingsAPI(initial: initial, updated: updated)
        let viewModel = SettingsViewModel(
            settingsAPI: api,
            skillsAPI: EmptySkillsAPI(),
            cache: TestCacheClient()
        )

        await viewModel.load()
        await viewModel.saveProfileSettings(
            name: "Sam",
            jobTitle: "",
            employer: "",
            dateOfBirth: nil,
            dateOfBirthEnabled: false,
            gender: "",
            pronouns: "",
            location: ""
        )

        XCTAssertEqual(api.updateCallCount, 1)
        let payload = try encodedPayload(try XCTUnwrap(api.lastUpdate))
        XCTAssertTrue(payload.keys.contains("date_of_birth"))
        XCTAssertTrue(payload["date_of_birth"] is NSNull)
        XCTAssertNil(payload["dateOfBirth"])
        XCTAssertNil(viewModel.settings?.dateOfBirth)
    }

    func testSaveProfileSettingsSurfacesErrorWhenLoadedSettingsAndRefetchDoNotMatchAuthenticatedUser() async {
        let initial = UserSettings(
            userId: "user-1",
            communicationStyle: nil,
            workingRelationship: nil,
            name: "Sam",
            jobTitle: nil,
            employer: nil,
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: "Boston",
            profileImageUrl: nil,
            enabledSkills: []
        )
        let api = RecordingSettingsAPI(initial: initial, updated: initial)
        let viewModel = SettingsViewModel(
            settingsAPI: api,
            skillsAPI: EmptySkillsAPI(),
            cache: TestCacheClient(),
            currentAuthUserIdProvider: { "user-2" }
        )

        await viewModel.load()
        await viewModel.saveProfileSettings(
            name: "Sam",
            jobTitle: "",
            employer: "",
            dateOfBirth: nil,
            dateOfBirthEnabled: false,
            gender: "",
            pronouns: "",
            location: "Seattle"
        )

        XCTAssertEqual(api.getSettingsCallCount, 2)
        XCTAssertEqual(api.updateCallCount, 0)
        XCTAssertNotNil(viewModel.profileSaveError)
    }

    func testSaveProfileSettingsMapsUpdateAuthFailureIntoSessionExpiredMessage() async {
        let initial = UserSettings(
            userId: "user-1",
            communicationStyle: nil,
            workingRelationship: nil,
            name: "Sam",
            jobTitle: "Founder",
            employer: "sideBar",
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: "Boston",
            profileImageUrl: nil,
            enabledSkills: []
        )
        let api = FailingProfileUpdateSettingsAPI(initial: initial, error: APIClientError.requestFailed(401))
        let viewModel = SettingsViewModel(
            settingsAPI: api,
            skillsAPI: EmptySkillsAPI(),
            cache: TestCacheClient()
        )

        await viewModel.load()
        await viewModel.saveProfileSettings(
            name: "Sam",
            jobTitle: "Founder",
            employer: "sideBar",
            dateOfBirth: nil,
            dateOfBirthEnabled: false,
            gender: "",
            pronouns: "",
            location: "Seattle"
        )

        XCTAssertEqual(api.updateCallCount, 1)
        XCTAssertEqual(viewModel.profileSaveError, "Session expired. Please sign in again.")
        XCTAssertEqual(viewModel.settingsSaveCompletionCount, 0)
    }

    private func encodedPayload(_ update: SettingsUpdate) throws -> [String: Any] {
        let data = try JSONEncoder().encode(update)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@MainActor
private final class RecordingSettingsAPI: SettingsProviding {
    let initial: UserSettings
    let updated: UserSettings
    var lastUpdate: SettingsUpdate?
    var getSettingsCallCount = 0
    var updateCallCount = 0

    init(initial: UserSettings, updated: UserSettings) {
        self.initial = initial
        self.updated = updated
    }

    func getSettings() async throws -> UserSettings {
        getSettingsCallCount += 1
        return initial
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        updateCallCount += 1
        lastUpdate = update
        return updated
    }

    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        return ProviderKeyStatusResponse(provider: nil, hasKey: false, keyLast4: nil)
    }

    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        _ = provider
        _ = apiKey
        return ProviderKeyStatusResponse(provider: nil, hasKey: true, keyLast4: "1234")
    }

    func deleteProviderKey(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        return ProviderKeyStatusResponse(provider: nil, hasKey: false, keyLast4: nil)
    }

    func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        ShortcutsTokenResponse(token: "")
    }

    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        ShortcutsTokenResponse(token: "")
    }

    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        _ = data
        _ = contentType
        _ = filename
    }

    func getProfileImage() async throws -> Data {
        Data()
    }

    func deleteProfileImage() async throws {
    }
}

private struct EmptySkillsAPI: SkillsProviding {
    func list() async throws -> SkillsResponse {
        SkillsResponse(skills: [])
    }
}

@MainActor
private final class FailingProfileUpdateSettingsAPI: SettingsProviding {
    let initial: UserSettings
    let error: Error
    var getSettingsCallCount = 0
    var updateCallCount = 0

    init(initial: UserSettings, error: Error) {
        self.initial = initial
        self.error = error
    }

    func getSettings() async throws -> UserSettings {
        getSettingsCallCount += 1
        return initial
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        _ = update
        updateCallCount += 1
        throw error
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

    func disconnectProviderConsumer(
        provider: String,
        source: ProviderKeyDisconnectSource,
        skillId: String?
    ) async throws -> ProviderKeyDisconnectResponse {
        _ = provider
        _ = source
        _ = skillId
        throw SettingsViewModelMockError.forced
    }

    func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        throw SettingsViewModelMockError.forced
    }

    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        throw SettingsViewModelMockError.forced
    }

    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        _ = data
        _ = contentType
        _ = filename
    }

    func getProfileImage() async throws -> Data {
        Data()
    }

    func deleteProfileImage() async throws {
    }
}
