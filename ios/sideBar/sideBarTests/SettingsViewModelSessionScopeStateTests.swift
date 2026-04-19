import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelSessionScopeStateTests: XCTestCase {
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

    func testInternalDiagnosticsRevealResetsWhenAuthenticatedUserChanges() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            cache: TestCacheClient(),
            userDefaults: defaults
        )
        let firstUser = UserSettings(
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
            enabledSkills: [],
            canAccessInternalDiagnostics: true
        )
        let secondUser = UserSettings(
            userId: "user-2",
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
            enabledSkills: [],
            canAccessInternalDiagnostics: true
        )

        viewModel.applySettingsResponse(firstUser)
        for _ in 0..<SettingsViewModel.internalDiagnosticsRevealTapThreshold {
            viewModel.handleInternalDiagnosticsRevealGesture()
        }
        XCTAssertTrue(viewModel.isInternalDiagnosticsLocallyUnlocked)

        viewModel.applySettingsResponse(secondUser)

        XCTAssertFalse(viewModel.isInternalDiagnosticsLocallyUnlocked)
        XCTAssertFalse(defaults.bool(forKey: AppStorageKeys.internalDiagnosticsUnlocked))
    }
}
