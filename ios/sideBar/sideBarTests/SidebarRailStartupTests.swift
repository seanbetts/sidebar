import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SidebarRailStartupTests: XCTestCase {
    func testShouldLoadProfileImageOnAppearRequiresAuthenticatedSessionAndProfileURL() {
        XCTAssertFalse(
            SidebarRail.shouldLoadProfileImageOnAppear(
                isAuthenticated: false,
                profileImageUrl: "https://example.com/profile.png",
                hasProfileImageData: false
            )
        )
        XCTAssertFalse(
            SidebarRail.shouldLoadProfileImageOnAppear(
                isAuthenticated: true,
                profileImageUrl: nil,
                hasProfileImageData: false
            )
        )
        XCTAssertFalse(
            SidebarRail.shouldLoadProfileImageOnAppear(
                isAuthenticated: true,
                profileImageUrl: "   ",
                hasProfileImageData: false
            )
        )
        XCTAssertFalse(
            SidebarRail.shouldLoadProfileImageOnAppear(
                isAuthenticated: true,
                profileImageUrl: "https://example.com/profile.png",
                hasProfileImageData: true
            )
        )
        XCTAssertTrue(
            SidebarRail.shouldLoadProfileImageOnAppear(
                isAuthenticated: true,
                profileImageUrl: "https://example.com/profile.png",
                hasProfileImageData: false
            )
        )
    }

    func testLoadProfileImageDeduplicatesConcurrentRequests() async {
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
            profileImageUrl: "https://example.com/profile.png",
            enabledSkills: []
        )
        let imageData = Data([0x01, 0x02, 0x03])
        let settingsAPI = BlockingProfileImageSettingsAPI(
            result: .success(settings),
            profileImageData: imageData
        )
        let viewModel = SettingsViewModel(
            settingsAPI: settingsAPI,
            skillsAPI: MockSkillsAPI(result: .failure(SettingsViewModelMockError.forced)),
            cache: TestCacheClient()
        )
        viewModel.applySettingsResponse(settings)

        async let firstLoad: Void = viewModel.loadProfileImage()
        async let secondLoad: Void = viewModel.loadProfileImage()

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(settingsAPI.profileImageCallCount, 1)

        settingsAPI.resumeProfileImageRequests()
        _ = await (firstLoad, secondLoad)

        XCTAssertEqual(viewModel.profileImageData, imageData)
    }
}

@MainActor
private final class BlockingProfileImageSettingsAPI: SettingsProviding {
    private let base: MockSettingsAPI
    private let resolvedProfileImageData: Data
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var profileImageCallCount: Int = 0

    init(result: Result<UserSettings, Error>, profileImageData: Data) {
        self.base = MockSettingsAPI(
            result: result,
            profileImageResult: .success(profileImageData)
        )
        self.resolvedProfileImageData = profileImageData
    }

    func resumeProfileImageRequests() {
        let resumableContinuations = continuations
        continuations.removeAll()
        for continuation in resumableContinuations {
            continuation.resume()
        }
    }

    func getSettings() async throws -> UserSettings {
        try await base.getSettings()
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        try await base.updateSettings(update)
    }

    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        try await base.getProviderKeyStatus(provider: provider)
    }

    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        try await base.upsertProviderKey(provider: provider, apiKey: apiKey)
    }

    func deleteProviderKey(provider: String?) async throws -> ProviderKeyStatusResponse {
        try await base.deleteProviderKey(provider: provider)
    }

    func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        try await base.getShortcutsToken()
    }

    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        try await base.rotateShortcutsToken()
    }

    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        try await base.uploadProfileImage(data: data, contentType: contentType, filename: filename)
    }

    func getProfileImage() async throws -> Data {
        profileImageCallCount += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        return resolvedProfileImageData
    }

    func deleteProfileImage() async throws {
        try await base.deleteProfileImage()
    }
}
