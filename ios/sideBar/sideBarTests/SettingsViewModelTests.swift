import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelTests: XCTestCase {
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

    func testLoadSkillsMapsTypedFailureMessage() async {
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .failure(APIClientError.requestFailed(503))),
            cache: TestCacheClient()
        )

        await viewModel.loadSkills()

        XCTAssertEqual(viewModel.skillsError, "Server is busy right now. Please try again.")
    }

    func testLoadShortcutsTokenMapsTypedFailureMessage() async {
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .failure(SettingsViewModelMockError.forced),
                tokenResult: .failure(APIClientError.requestFailed(401))
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: TestCacheClient()
        )

        await viewModel.loadShortcutsToken()

        XCTAssertEqual(viewModel.shortcutsError, "Session expired. Please sign in again.")
    }

    func testRotateShortcutsTokenMapsTypedFailureMessage() async {
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .failure(SettingsViewModelMockError.forced),
                tokenResult: .failure(APIClientError.requestFailed(503))
            ),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: TestCacheClient()
        )

        await viewModel.rotateShortcutsToken()

        XCTAssertEqual(viewModel.shortcutsError, "Server is busy right now. Please try again.")
    }

    func testSetSkillEnabledUpdatesLocalStateWithoutForcingSettingsOrSkillsReload() async {
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
        XCTAssertEqual(skillsListRecorder.listCallCount, 1)
        await viewModel.setSkillEnabled(id: "s1", enabled: true)

        XCTAssertEqual(settingsReadRecorder.getSettingsCallCount, 0)
        XCTAssertEqual(skillsListRecorder.listCallCount, 1)
        let removedKeys = cache.removedKeysSnapshot()
        XCTAssertFalse(removedKeys.contains(CacheKeys.userSettings))
        XCTAssertFalse(removedKeys.contains(CacheKeys.skillsList))
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
