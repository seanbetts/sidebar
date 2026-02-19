import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsVMAssistantDisplayNameTests: XCTestCase {
    func testAssistantDisplayNameFallsBackWhenSettingsMissing() {
        let viewModel = SettingsViewModel(
            settingsAPI: AssistantNameMockSettingsAPI(result: .failure(AssistantNameMockError.forced)),
            skillsAPI: AssistantNameMockSkillsAPI(),
            cache: TestCacheClient()
        )

        XCTAssertEqual(viewModel.assistantDisplayName, "sideBar")
    }

    func testAssistantDisplayNameUsesTrimmedAssistantIdentityName() async {
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
            profileImageUrl: nil,
            assistantIdentity: AssistantIdentitySettings(
                name: "  Navigator  ",
                tone: nil,
                values: nil,
                boundaries: nil
            ),
            enabledSkills: []
        )
        let viewModel = SettingsViewModel(
            settingsAPI: AssistantNameMockSettingsAPI(result: .success(settings)),
            skillsAPI: AssistantNameMockSkillsAPI(),
            cache: TestCacheClient()
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.assistantDisplayName, "Navigator")
    }

    func testAssistantDisplayNameFallsBackWhenAssistantNameIsBlank() async {
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
            profileImageUrl: nil,
            assistantIdentity: AssistantIdentitySettings(
                name: "   ",
                tone: nil,
                values: nil,
                boundaries: nil
            ),
            enabledSkills: []
        )
        let viewModel = SettingsViewModel(
            settingsAPI: AssistantNameMockSettingsAPI(result: .success(settings)),
            skillsAPI: AssistantNameMockSkillsAPI(),
            cache: TestCacheClient()
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.assistantDisplayName, "sideBar")
    }

    func testDisplayNameForAssistantIdentitySkillUsesAssistantName() async {
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
            profileImageUrl: nil,
            assistantIdentity: AssistantIdentitySettings(
                name: "Navigator",
                tone: nil,
                values: nil,
                boundaries: nil
            ),
            enabledSkills: []
        )
        let viewModel = SettingsViewModel(
            settingsAPI: AssistantNameMockSettingsAPI(result: .success(settings)),
            skillsAPI: AssistantNameMockSkillsAPI(),
            cache: TestCacheClient()
        )
        let skill = SkillItem(
            id: "assistant-identity",
            name: "Assistant Identity",
            description: "System-managed identity.",
            category: "System",
            userToggleable: false
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.displayName(for: skill), "Navigator's Identity")
    }

    func testDisplayNameForAssistantSoulSkillUsesAssistantName() async {
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
            profileImageUrl: nil,
            assistantIdentity: AssistantIdentitySettings(
                name: "Navigator",
                tone: nil,
                values: nil,
                boundaries: nil
            ),
            enabledSkills: []
        )
        let viewModel = SettingsViewModel(
            settingsAPI: AssistantNameMockSettingsAPI(result: .success(settings)),
            skillsAPI: AssistantNameMockSkillsAPI(),
            cache: TestCacheClient()
        )
        let skill = SkillItem(
            id: "assistant-soul",
            name: "Assistant Soul",
            description: "System-managed soul.",
            category: "System",
            userToggleable: false
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.displayName(for: skill), "Navigator's Soul")
    }

    func testDisplayNameForNonAssistantSkillIsUnchanged() {
        let viewModel = SettingsViewModel(
            settingsAPI: AssistantNameMockSettingsAPI(result: .failure(AssistantNameMockError.forced)),
            skillsAPI: AssistantNameMockSkillsAPI(),
            cache: TestCacheClient()
        )
        let skill = SkillItem(
            id: "fs",
            name: "Files",
            description: "File access.",
            category: "Documents"
        )

        XCTAssertEqual(viewModel.displayName(for: skill), "Files")
    }

    func testDisplayDescriptionReplacesAssistantNamePlaceholder() async {
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
            profileImageUrl: nil,
            assistantIdentity: AssistantIdentitySettings(
                name: "Navigator",
                tone: nil,
                values: nil,
                boundaries: nil
            ),
            enabledSkills: []
        )
        let viewModel = SettingsViewModel(
            settingsAPI: AssistantNameMockSettingsAPI(result: .success(settings)),
            skillsAPI: AssistantNameMockSkillsAPI(),
            cache: TestCacheClient()
        )
        let skill = SkillItem(
            id: "ui-theme",
            name: "UI Theme",
            description: "Allow {name} to switch between light and dark mode",
            category: "System"
        )

        await viewModel.load()

        XCTAssertEqual(
            viewModel.displayDescription(for: skill),
            "Allow Navigator to switch between light and dark mode"
        )
    }

    func testDisplayDescriptionRemovesTrailingPeriodForConsistency() {
        let viewModel = SettingsViewModel(
            settingsAPI: AssistantNameMockSettingsAPI(result: .failure(AssistantNameMockError.forced)),
            skillsAPI: AssistantNameMockSkillsAPI(),
            cache: TestCacheClient()
        )
        let skill = SkillItem(
            id: "notes",
            name: "Notes",
            description: "Create and update notes.",
            category: "Productivity"
        )

        XCTAssertEqual(viewModel.displayDescription(for: skill), "Create and update notes")
    }
}

private enum AssistantNameMockError: Error {
    case forced
}

private struct AssistantNameMockSettingsAPI: SettingsProviding {
    let result: Result<UserSettings, Error>

    func getSettings() async throws -> UserSettings {
        try result.get()
    }

    func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        throw AssistantNameMockError.forced
    }

    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        throw AssistantNameMockError.forced
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        throw AssistantNameMockError.forced
    }

    func getProfileImage() async throws -> Data {
        throw AssistantNameMockError.forced
    }

    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
    }

    func deleteProfileImage() async throws {
    }
}

private struct AssistantNameMockSkillsAPI: SkillsProviding {
    func list() async throws -> SkillsResponse {
        SkillsResponse(skills: [])
    }
}
