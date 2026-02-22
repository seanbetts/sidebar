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
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .failure(SettingsViewModelMockError.forced)),
            cache: cache
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.settings?.name, "Cached User")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadUsesUserScopedCacheKeyWhenAuthUserIdAvailable() async {
        let legacyCached = UserSettings(
            userId: "legacy-user",
            communicationStyle: nil,
            workingRelationship: nil,
            name: "Legacy User",
            jobTitle: nil,
            employer: nil,
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: nil,
            profileImageUrl: nil,
            enabledSkills: []
        )
        let scopedCached = UserSettings(
            userId: "user-1",
            communicationStyle: nil,
            workingRelationship: nil,
            name: "Scoped User",
            jobTitle: nil,
            employer: nil,
            dateOfBirth: nil,
            gender: nil,
            pronouns: nil,
            location: nil,
            profileImageUrl: nil,
            enabledSkills: []
        )
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.userSettings, value: legacyCached, ttlSeconds: 60)
        cache.set(key: "\(CacheKeys.userSettings).user-1", value: scopedCached, ttlSeconds: 60)

        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .failure(SettingsViewModelMockError.forced)),
            cache: cache,
            currentAuthUserIdProvider: { "user-1" }
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.settings?.name, "Scoped User")
    }

    func testLoadSkillsCachesFreshData() async {
        let response = SkillsResponse(skills: [
            SkillItem(id: "s1", name: "Skill", description: "Desc", category: "General")
        ])
        let cache = TestCacheClient()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .success(response)),
            cache: cache
        )

        await viewModel.loadSkills()

        let cached: SkillsResponse? = cache.get(key: CacheKeys.skillsList)
        XCTAssertEqual(cached?.skills.first?.id, "s1")
        XCTAssertEqual(viewModel.skills.first?.id, "s1")
    }

    func testSetSkillEnabledInvalidatesCachesAndForceRefreshesSettingsAndSkills() async {
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
            profileImageUrl: nil,
            enabledSkills: []
        )
        let refreshed = UserSettings(
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
        let settingsReadRecorder = SettingsReadRecorder()
        let skillsListRecorder = SkillsListRecorder()
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.userSettings, value: initial, ttlSeconds: 60)
        cache.set(key: CacheKeys.skillsList, value: SkillsResponse(skills: []), ttlSeconds: 60)
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(refreshed),
                updateResult: .success(refreshed),
                readRecorder: settingsReadRecorder
            ),
            skillsAPI: MockSkillsAPI(
                result: .success(
                    SkillsResponse(skills: [
                        SkillItem(id: "s1", name: "Skill", description: "Desc", category: "General")
                    ])
                ),
                listRecorder: skillsListRecorder
            ),
            cache: cache
        )

        viewModel.applySettingsResponse(initial)
        await viewModel.loadSkills()
        XCTAssertEqual(skillsListRecorder.listCallCount, 0)
        await viewModel.setSkillEnabled(id: "s1", enabled: true)

        XCTAssertEqual(settingsReadRecorder.getSettingsCallCount, 1)
        XCTAssertEqual(skillsListRecorder.listCallCount, 1)
        let removedKeys = cache.removedKeysSnapshot()
        XCTAssertTrue(removedKeys.contains(CacheKeys.userSettings))
        XCTAssertTrue(removedKeys.contains(CacheKeys.skillsList))
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
                profileImageResult: .failure(SettingsViewModelMockError.forced)
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: cache
        )

        await viewModel.load()
        await viewModel.loadProfileImage()

        XCTAssertEqual(viewModel.profileImageData, cachedData)
    }

    func testLoadProfileImageUsesUserScopedCacheKeyWhenAuthUserIdAvailable() async {
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
        let legacyData = Data([0xAA])
        let scopedData = Data([0x01, 0x02, 0x03])
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.profileImage, value: legacyData, ttlSeconds: 60)
        cache.set(key: "\(CacheKeys.profileImage).user-1", value: scopedData, ttlSeconds: 60)
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(settings),
                profileImageResult: .failure(SettingsViewModelMockError.forced)
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: cache,
            currentAuthUserIdProvider: { "user-1" }
        )

        await viewModel.load()
        await viewModel.loadProfileImage()

        XCTAssertEqual(viewModel.profileImageData, scopedData)
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

enum SettingsViewModelMockError: Error {
    case forced
}

@MainActor
struct MockSettingsAPI: SettingsProviding {
    let result: Result<UserSettings, Error>
    let tokenResult: Result<ShortcutsTokenResponse, Error>
    let updateResult: Result<UserSettings, Error>
    let profileImageResult: Result<Data, Error>
    let readRecorder: SettingsReadRecorder?
    let updateRecorder: UpdateRecorder?
    let providerKeyRecorder: ProviderKeyRecorder?

    init(
        result: Result<UserSettings, Error>,
        tokenResult: Result<ShortcutsTokenResponse, Error> = .failure(SettingsViewModelMockError.forced),
        updateResult: Result<UserSettings, Error> = .failure(SettingsViewModelMockError.forced),
        profileImageResult: Result<Data, Error> = .failure(SettingsViewModelMockError.forced),
        readRecorder: SettingsReadRecorder? = nil,
        updateRecorder: UpdateRecorder? = nil,
        providerKeyRecorder: ProviderKeyRecorder? = nil
    ) {
        self.result = result
        self.tokenResult = tokenResult
        self.updateResult = updateResult
        self.profileImageResult = profileImageResult
        self.readRecorder = readRecorder
        self.updateRecorder = updateRecorder
        self.providerKeyRecorder = providerKeyRecorder
    }

    func getSettings() async throws -> UserSettings {
        readRecorder?.getSettingsCallCount += 1
        return try result.get()
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
        let normalizedProvider = provider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasKey = normalizedProvider.flatMap { providerKeyRecorder?.statusByProvider[$0] } ?? false
        return ProviderKeyStatusResponse(provider: normalizedProvider, hasKey: hasKey, keyLast4: nil)
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

struct MockSkillsAPI: SkillsProviding {
    let result: Result<SkillsResponse, Error>
    let installResult: Result<StoreSkillInstallResponse, Error>
    let uninstallResult: Result<StoreSkillInstallResponse, Error>
    let listRecorder: SkillsListRecorder?
    let installRecorder: SkillsInstallRecorder?
    let uninstallRecorder: SkillsUninstallRecorder?

    init(
        result: Result<SkillsResponse, Error>,
        installResult: Result<StoreSkillInstallResponse, Error> = .failure(SettingsViewModelMockError.forced),
        uninstallResult: Result<StoreSkillInstallResponse, Error> = .failure(SettingsViewModelMockError.forced),
        listRecorder: SkillsListRecorder? = nil,
        installRecorder: SkillsInstallRecorder? = nil,
        uninstallRecorder: SkillsUninstallRecorder? = nil
    ) {
        self.result = result
        self.installResult = installResult
        self.uninstallResult = uninstallResult
        self.listRecorder = listRecorder
        self.installRecorder = installRecorder
        self.uninstallRecorder = uninstallRecorder
    }

    func list() async throws -> SkillsResponse {
        listRecorder?.listCallCount += 1
        return try result.get()
    }

    func installStoreSkill(
        skillId: String,
        providerKeys: [StoreSkillProviderKeyInput]
    ) async throws -> StoreSkillInstallResponse {
        installRecorder?.callCount += 1
        installRecorder?.lastSkillId = skillId
        installRecorder?.lastProviderKeys = providerKeys
        return try installResult.get()
    }

    func uninstallStoreSkill(
        skillId: String
    ) async throws -> StoreSkillInstallResponse {
        uninstallRecorder?.callCount += 1
        uninstallRecorder?.lastSkillId = skillId
        return try uninstallResult.get()
    }
}

final class UpdateRecorder {
    var callCount: Int = 0
    var lastUpdate: SettingsUpdate?
}

final class SettingsReadRecorder {
    var getSettingsCallCount: Int = 0
}

final class ProviderKeyRecorder {
    var statusCallCount: Int = 0
    var upsertCallCount: Int = 0
    var deleteCallCount: Int = 0
    var lastStatusProvider: String?
    var lastUpsertProvider: String?
    var lastUpsertApiKey: String?
    var lastDeleteProvider: String?
    var statusByProvider: [String: Bool] = [:]
}

final class SkillsInstallRecorder {
    var callCount: Int = 0
    var lastSkillId: String?
    var lastProviderKeys: [StoreSkillProviderKeyInput]?
}

final class SkillsUninstallRecorder {
    var callCount: Int = 0
    var lastSkillId: String?
}

final class SkillsListRecorder {
    var listCallCount: Int = 0
}
