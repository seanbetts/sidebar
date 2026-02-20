import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelAssistantRealtimeTests: XCTestCase {
    func testApplyAssistantSettingsUpdateMergesIdentityAndCachesSettings() async {
        let initial = UserSettings(
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
            assistantIdentity: AssistantIdentitySettings(
                name: "sideBar",
                tone: "direct",
                values: nil,
                boundaries: nil
            ),
            assistantIdentityMeta: AgentFieldMeta(
                updatedAt: "2026-02-18T00:00:00Z",
                version: 1,
                reason: nil
            ),
            enabledSkills: []
        )
        let cache = TestCacheClient()
        let viewModel = SettingsViewModel(
            settingsAPI: SequencedSettingsAPI(settings: [initial]),
            skillsAPI: EmptySkillsAPI(),
            cache: cache
        )

        await viewModel.load()
        viewModel.applyAssistantSettingsUpdate(
            AssistantSettingsRealtimeUpdate(
                assistantIdentity: AssistantIdentitySettings(
                    name: "Navigator",
                    tone: "direct",
                    values: nil,
                    boundaries: nil
                ),
                assistantIdentityMeta: AgentFieldMeta(
                    updatedAt: "2026-02-18T01:00:00Z",
                    version: 2,
                    reason: "test"
                ),
                assistantSoul: nil,
                assistantSoulMeta: nil,
                requiresRefresh: false
            )
        )

        XCTAssertEqual(viewModel.assistantDisplayName, "Navigator")
        let cached: UserSettings? = cache.get(key: CacheKeys.userSettings)
        XCTAssertEqual(cached?.assistantIdentity?.name, "Navigator")
        XCTAssertEqual(cached?.assistantIdentityMeta?.version, 2)
    }

    func testApplyAssistantSettingsUpdateRefreshesWhenRequested() async {
        let initial = UserSettings(
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
            assistantIdentity: AssistantIdentitySettings(
                name: "sideBar",
                tone: nil,
                values: nil,
                boundaries: nil
            ),
            enabledSkills: []
        )
        let refreshed = UserSettings(
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
            assistantIdentity: AssistantIdentitySettings(
                name: "Reloaded",
                tone: nil,
                values: nil,
                boundaries: nil
            ),
            enabledSkills: []
        )
        let api = SequencedSettingsAPI(settings: [initial, refreshed])
        let viewModel = SettingsViewModel(
            settingsAPI: api,
            skillsAPI: EmptySkillsAPI(),
            cache: TestCacheClient()
        )

        await viewModel.load()
        viewModel.applyAssistantSettingsUpdate(
            AssistantSettingsRealtimeUpdate(
                assistantIdentity: nil,
                assistantIdentityMeta: nil,
                assistantSoul: nil,
                assistantSoulMeta: nil,
                requiresRefresh: true
            )
        )
        for _ in 0..<8 {
            if viewModel.assistantDisplayName == "Reloaded" {
                break
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertEqual(api.getSettingsCallCount, 2)
        XCTAssertEqual(viewModel.assistantDisplayName, "Reloaded")
    }
}

@MainActor
private final class SequencedSettingsAPI: SettingsProviding {
    private let settings: [UserSettings]
    private(set) var getSettingsCallCount = 0

    init(settings: [UserSettings]) {
        self.settings = settings
    }

    func getSettings() async throws -> UserSettings {
        let index = min(getSettingsCallCount, settings.count - 1)
        getSettingsCallCount += 1
        return settings[index]
    }

    func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        throw SettingsRealtimeTestError.forced
    }

    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        throw SettingsRealtimeTestError.forced
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        _ = update
        throw SettingsRealtimeTestError.forced
    }

    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        throw SettingsRealtimeTestError.forced
    }

    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        _ = provider
        _ = apiKey
        throw SettingsRealtimeTestError.forced
    }

    func deleteProviderKey(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        throw SettingsRealtimeTestError.forced
    }

    func getProfileImage() async throws -> Data {
        throw SettingsRealtimeTestError.forced
    }

    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        _ = data
        _ = contentType
        _ = filename
    }

    func deleteProfileImage() async throws {
    }
}

private struct EmptySkillsAPI: SkillsProviding {
    func list() async throws -> SkillsResponse {
        SkillsResponse(skills: [])
    }
}

private enum SettingsRealtimeTestError: Error {
    case forced
}
