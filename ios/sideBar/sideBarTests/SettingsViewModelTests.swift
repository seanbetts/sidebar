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

    init(
        result: Result<UserSettings, Error>,
        tokenResult: Result<ShortcutsTokenResponse, Error> = .failure(MockError.forced),
        updateResult: Result<UserSettings, Error> = .failure(MockError.forced),
        profileImageResult: Result<Data, Error> = .failure(MockError.forced)
    ) {
        self.result = result
        self.tokenResult = tokenResult
        self.updateResult = updateResult
        self.profileImageResult = profileImageResult
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
        _ = update
        return try updateResult.get()
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
