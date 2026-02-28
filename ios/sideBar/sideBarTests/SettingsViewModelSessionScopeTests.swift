import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelSessionScopeTests: XCTestCase {
    func testSaveUserSettingsSkipsWhenSettingsBelongToDifferentAuthenticatedUser() async {
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
        let recorder = UpdateRecorder()
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(
                result: .success(initial),
                updateResult: .success(initial),
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

        XCTAssertEqual(recorder.callCount, 0)
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
