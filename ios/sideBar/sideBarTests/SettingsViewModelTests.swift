import XCTest
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
}

private enum MockError: Error {
    case forced
}

private struct MockSettingsAPI: SettingsProviding {
    let result: Result<UserSettings, Error>

    func getSettings() async throws -> UserSettings {
        try result.get()
    }
}

private struct MockSkillsAPI: SkillsProviding {
    let result: Result<SkillsResponse, Error>

    func list() async throws -> SkillsResponse {
        try result.get()
    }
}
