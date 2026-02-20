import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testLoadUsesCacheOnFailure() async {
        let cached = UserSettings(
            userId: "user-1",
            communicationStyle: "friendly",
            workingRelationship: nil,
            name: "Cached User",
            jobTitle: nil,
            employer: nil,
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: nil,
            profileImageUrl: "https://example.com",
            enabledSkills: []
        )
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.userSettings, value: cached, ttlSeconds: 60)
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(MockError.forced)),
            skillsAPI: MockSkillsAPI(result: .failure(MockError.forced)),
            cache: cache
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.settings?.name, "Cached User")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadSkillsCachesFreshData() async {
        let response = SkillsResponse(skills: [
            SkillItem(id: "s1", name: "Skill", description: "Desc", category: "General")
        ])
        let cache = TestCacheClient()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(MockError.forced)),
            skillsAPI: MockSkillsAPI(result: .success(response)),
            cache: cache
        )

        await viewModel.loadSkills()

        let cached: SkillsResponse? = cache.get(key: CacheKeys.skillsList)
        XCTAssertEqual(cached?.skills.first?.id, "s1")
        XCTAssertEqual(viewModel.skills.first?.id, "s1")
    }

    func testSetSkillEnabledUpdatesSettings() async {
        let settings = UserSettings(
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
            profileImageUrl: nil,
            enabledSkills: []
        )
        let updated = UserSettings(
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
            profileImageUrl: nil,
            enabledSkills: ["s1"]
        )
        let cache = TestCacheClient()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(settings),
                updateResult: .success(updated)
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: cache
        )

        await viewModel.load()
        await viewModel.setSkillEnabled(id: "s1", enabled: true)

        XCTAssertEqual(viewModel.settings?.enabledSkills, ["s1"])
    }

    func testSetSkillEnabledIgnoresLockedSkill() async throws {
        let settings = UserSettings(
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
            profileImageUrl: nil,
            enabledSkills: ["assistant-identity"]
        )
        let recorder = UpdateRecorder()
        let cache = TestCacheClient()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(settings),
                updateRecorder: recorder
            ),
            skillsAPI: MockSkillsAPI(
                result: .success(
                    SkillsResponse(skills: [
                        SkillItem(
                            id: "assistant-identity",
                            name: "Assistant Identity",
                            description: "System-managed identity.",
                            category: "System",
                            userToggleable: false
                        )
                    ])
                )
            ),
            cache: cache
        )

        await viewModel.load()
        await viewModel.loadSkills()
        await viewModel.setSkillEnabled(id: "assistant-identity", enabled: false)

        XCTAssertEqual(recorder.callCount, 0)
        XCTAssertEqual(viewModel.settings?.enabledSkills, ["assistant-identity"])
    }

    func testSetAllSkillsEnabledKeepsRequiredSkillsWhenDisabling() async throws {
        let settings = UserSettings(
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
            profileImageUrl: nil,
            enabledSkills: ["assistant-identity", "fs"]
        )
        let updated = UserSettings(
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
            profileImageUrl: nil,
            enabledSkills: ["assistant-identity"]
        )
        let recorder = UpdateRecorder()
        let cache = TestCacheClient()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(settings),
                updateResult: .success(updated),
                updateRecorder: recorder
            ),
            skillsAPI: MockSkillsAPI(
                result: .success(
                    SkillsResponse(skills: [
                        SkillItem(
                            id: "assistant-identity",
                            name: "Assistant Identity",
                            description: "System-managed identity.",
                            category: "System",
                            userToggleable: false
                        ),
                        SkillItem(id: "fs", name: "Files", description: "File access.", category: "Documents")
                    ])
                )
            ),
            cache: cache
        )

        await viewModel.load()
        await viewModel.loadSkills()
        await viewModel.setAllSkillsEnabled(false)

        XCTAssertEqual(recorder.callCount, 1)
        let update = try XCTUnwrap(recorder.lastUpdate)
        let payload = try encodedPayload(update)
        XCTAssertEqual(payload["enabled_skills"] as? [String], ["assistant-identity"])
    }

    func testLoadProfileImageUsesCacheOnFailure() async {
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
            profileImageUrl: "https://example.com/profile.png",
            enabledSkills: []
        )
        let cachedData = Data([0x01, 0x02, 0x03])
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.profileImage, value: cachedData, ttlSeconds: 60)
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(settings),
                profileImageResult: .failure(MockError.forced)
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: cache
        )

        await viewModel.load()
        await viewModel.loadProfileImage()

        XCTAssertEqual(viewModel.profileImageData, cachedData)
    }

    func testSaveUserSettingsSkipsUnchangedPayload() async throws {
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
            assistantIdentity: AssistantIdentitySettings(
                name: "sideBar",
                tone: "direct",
                values: "clarity",
                boundaries: "no guessing"
            ),
            enabledSkills: []
        )
        let recorder = UpdateRecorder()
        let cache = TestCacheClient()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(initial),
                updateResult: .success(initial),
                updateRecorder: recorder
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: cache
        )

        await viewModel.load()
        await viewModel.saveUserSettings(
            communicationStyle: "Concise",
            workingRelationship: "Direct"
        )

        XCTAssertEqual(recorder.callCount, 0)
    }

    func testSaveUserSettingsSendsPromptUpdates() async throws {
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
            assistantIdentity: AssistantIdentitySettings(
                name: "sideBar",
                tone: "direct",
                values: "clarity",
                boundaries: "no guessing"
            ),
            enabledSkills: []
        )
        let updated = UserSettings(
            userId: "user-1",
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
            assistantIdentity: AssistantIdentitySettings(
                name: "Navigator",
                tone: "direct",
                values: "clarity",
                boundaries: "no guessing"
            ),
            enabledSkills: []
        )
        let recorder = UpdateRecorder()
        let cache = TestCacheClient()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(initial),
                updateResult: .success(updated),
                updateRecorder: recorder
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: cache
        )

        await viewModel.load()
        await viewModel.saveUserSettings(
            communicationStyle: "Detailed",
            workingRelationship: "Direct"
        )

        XCTAssertEqual(recorder.callCount, 1)
        let update = try XCTUnwrap(recorder.lastUpdate)
        let payload = try encodedPayload(update)
        XCTAssertEqual(payload["communication_style"] as? String, "Detailed")
        XCTAssertFalse(payload.keys.contains("assistant_identity"))
    }

    private func encodedPayload(_ update: SettingsUpdate) throws -> [String: Any] {
        let data = try JSONEncoder().encode(update)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private enum MockError: Error {
    case forced
}

@MainActor
private struct MockSettingsAPI: SettingsProviding {
    let result: Result<UserSettings, Error>
    let tokenResult: Result<ShortcutsTokenResponse, Error>
    let updateResult: Result<UserSettings, Error>
    let profileImageResult: Result<Data, Error>
    let updateRecorder: UpdateRecorder?
    let providerKeyRecorder: ProviderKeyRecorder?

    init(
        result: Result<UserSettings, Error>,
        tokenResult: Result<ShortcutsTokenResponse, Error> = .failure(MockError.forced),
        updateResult: Result<UserSettings, Error> = .failure(MockError.forced),
        profileImageResult: Result<Data, Error> = .failure(MockError.forced),
        updateRecorder: UpdateRecorder? = nil,
        providerKeyRecorder: ProviderKeyRecorder? = nil
    ) {
        self.result = result
        self.tokenResult = tokenResult
        self.updateResult = updateResult
        self.profileImageResult = profileImageResult
        self.updateRecorder = updateRecorder
        self.providerKeyRecorder = providerKeyRecorder
    }

    func getSettings() async throws -> UserSettings {
        try result.get()
    }

    func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        try tokenResult.get()
    }

    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        try tokenResult.get()
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        updateRecorder?.callCount += 1
        updateRecorder?.lastUpdate = update
        return try updateResult.get()
    }

    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        providerKeyRecorder?.statusCallCount += 1
        providerKeyRecorder?.lastStatusProvider = provider
        return ProviderKeyStatusResponse(provider: nil, hasKey: false, keyLast4: nil)
    }

    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        providerKeyRecorder?.upsertCallCount += 1
        providerKeyRecorder?.lastUpsertProvider = provider
        providerKeyRecorder?.lastUpsertApiKey = apiKey
        return ProviderKeyStatusResponse(provider: nil, hasKey: true, keyLast4: "1234")
    }

    func deleteProviderKey(provider: String?) async throws -> ProviderKeyStatusResponse {
        providerKeyRecorder?.deleteCallCount += 1
        providerKeyRecorder?.lastDeleteProvider = provider
        return ProviderKeyStatusResponse(provider: nil, hasKey: false, keyLast4: nil)
    }

    func getProfileImage() async throws -> Data {
        try profileImageResult.get()
    }

    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        _ = data
        _ = contentType
        _ = filename
    }

    func deleteProfileImage() async throws {
    }
}

private struct MockSkillsAPI: SkillsProviding {
    let result: Result<SkillsResponse, Error>

    func list() async throws -> SkillsResponse {
        try result.get()
    }
}

private final class UpdateRecorder {
    var callCount: Int = 0
    var lastUpdate: SettingsUpdate?
}

private final class ProviderKeyRecorder {
    var statusCallCount: Int = 0
    var upsertCallCount: Int = 0
    var deleteCallCount: Int = 0
    var lastStatusProvider: String?
    var lastUpsertProvider: String?
    var lastUpsertApiKey: String?
    var lastDeleteProvider: String?
}
