import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelCacheScopeTests: XCTestCase {
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
}
