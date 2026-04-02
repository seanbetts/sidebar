import XCTest
import sideBarShared
@testable import sideBar

@MainActor
final class SettingsViewModelPrimaryProviderTests: XCTestCase {
    func testSavePrimaryProviderSendsProviderUpdate() async throws {
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
            aiPrimaryProvider: "anthropic",
            enabledSkills: []
        )
        let api = PrimaryProviderSettingsAPI(initial: initial)
        let viewModel = SettingsViewModel(
            settingsAPI: api,
            skillsAPI: PrimaryProviderEmptySkillsAPI(),
            cache: TestCacheClient()
        )

        await viewModel.load()
        await viewModel.savePrimaryProvider(.openai)

        XCTAssertEqual(api.updateCallCount, 1)
        let update = try XCTUnwrap(api.lastUpdate)
        let payload = try encodedPayload(update)
        XCTAssertEqual(payload["ai_primary_provider"] as? String, "openai")
        XCTAssertEqual(viewModel.settings?.aiPrimaryProvider, "openai")
    }

    func testSavePrimaryProviderKeyUsesSelectedProvider() async throws {
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
            aiPrimaryProvider: "google",
            aiPrimaryProviderHasKey: false,
            aiPrimaryProviderKeyLast4: nil,
            enabledSkills: []
        )
        let api = PrimaryProviderSettingsAPI(initial: initial)
        let viewModel = SettingsViewModel(
            settingsAPI: api,
            skillsAPI: PrimaryProviderEmptySkillsAPI(),
            cache: TestCacheClient()
        )

        await viewModel.load()
        let success = await viewModel.savePrimaryProviderKey(
            provider: .google,
            apiKey: "AIzaSyValidGoogleKey12345"
        )

        XCTAssertTrue(success)
        XCTAssertEqual(api.upsertCallCount, 1)
        XCTAssertEqual(api.lastUpsertProvider, "google")
        XCTAssertEqual(api.lastUpsertApiKey, "AIzaSyValidGoogleKey12345")
    }

    func testSignedInRecoveryStateShowsProviderRecoveryWhenSelectedProviderHasNoKey() async {
        let onboardingState = OnboardingState(
            status: .completed,
            providerReady: true,
            currentOnboardingStep: .completed,
            isOnboardingComplete: true,
            intent: .chat,
            milestones: OnboardingMilestones(
                providerConnected: "2026-03-31T12:00:00Z",
                firstOutcomeCompleted: "2026-03-31T12:30:00Z",
                profileBasicsSet: nil,
                communicationStyleSet: nil,
                secondaryTourSeen: "2026-03-31T12:31:00Z"
            ),
            permissions: OnboardingPermissions(
                location: .granted,
                notifications: .granted
            ),
            lastPromptedAt: nil
        )
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.getResult = .success(onboardingState)
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            onboardingAPI: onboardingAPI,
            cache: TestCacheClient()
        )
        viewModel.applySettingsResponse(
            UserSettings(
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
                aiPrimaryProvider: "anthropic",
                aiPrimaryProviderHasKey: false,
                enabledSkills: []
            )
        )

        await viewModel.loadOnboarding()

        XCTAssertEqual(viewModel.onboardingState, onboardingState)
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .providerRecovery)
    }

    func testSignedInRecoveryStateShowsProviderRecoveryWhenNoPrimaryProviderIsConfigured() async {
        let onboardingState = OnboardingState(
            status: .completed,
            providerReady: false,
            currentOnboardingStep: .completed,
            isOnboardingComplete: true,
            intent: .chat,
            milestones: OnboardingMilestones(
                providerConnected: nil,
                firstOutcomeCompleted: nil,
                profileBasicsSet: nil,
                communicationStyleSet: nil,
                secondaryTourSeen: "2026-03-31T12:31:00Z"
            ),
            permissions: OnboardingPermissions(
                location: .granted,
                notifications: .granted
            ),
            lastPromptedAt: nil
        )
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.getResult = .success(onboardingState)
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .failure(SettingsViewModelMockError.forced)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            onboardingAPI: onboardingAPI,
            cache: TestCacheClient()
        )
        viewModel.applySettingsResponse(
            UserSettings(
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
                aiPrimaryProvider: nil,
                aiPrimaryProviderHasKey: false,
                enabledSkills: []
            )
        )

        await viewModel.loadOnboarding()

        XCTAssertEqual(viewModel.onboardingState, onboardingState)
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .providerRecovery)
    }

    func testSavePrimaryProviderKeyAlsoSelectsProviderWhenMissing() async throws {
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
            aiPrimaryProvider: nil,
            aiPrimaryProviderHasKey: false,
            aiPrimaryProviderKeyLast4: nil,
            enabledSkills: []
        )
        let api = PrimaryProviderSettingsAPI(initial: initial)
        let viewModel = SettingsViewModel(
            settingsAPI: api,
            skillsAPI: PrimaryProviderEmptySkillsAPI(),
            cache: TestCacheClient()
        )

        await viewModel.load()
        let success = await viewModel.savePrimaryProviderKey(
            provider: .anthropic,
            apiKey: "test-anthropic-key"
        )

        XCTAssertTrue(success)
        XCTAssertEqual(api.upsertCallCount, 1)
        XCTAssertEqual(api.updateCallCount, 1)
        XCTAssertEqual(api.lastUpdate?.aiPrimaryProvider, "anthropic")
        XCTAssertEqual(viewModel.settings?.aiPrimaryProvider, "anthropic")
        XCTAssertTrue(viewModel.settings?.aiPrimaryProviderHasKey == true)
    }

    func testSavePrimaryProviderKeyRefreshesIntoFeatureDiscoveryEvenWhenPermissionsRemainUnset() async throws {
        let refreshedSettings = UserSettings(
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
            aiPrimaryProvider: "anthropic",
            aiPrimaryProviderHasKey: true,
            aiPrimaryProviderKeyLast4: "1234",
            enabledSkills: []
        )
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.getResults = [
            .success(
                OnboardingState(
                    status: .dismissed,
                    providerReady: false,
                    currentOnboardingStep: .providerRecovery,
                    isOnboardingComplete: false,
                    intent: .chat,
                    milestones: OnboardingMilestones(
                        providerConnected: nil,
                        firstOutcomeCompleted: nil,
                        profileBasicsSet: nil,
                        communicationStyleSet: nil,
                        secondaryTourSeen: nil
                    ),
                    permissions: OnboardingPermissions(
                        location: .notAsked,
                        notifications: .denied
                    ),
                    lastPromptedAt: nil
                )
            ),
            .success(
                OnboardingState(
                    status: .dismissed,
                    providerReady: true,
                    currentOnboardingStep: .featureDiscovery,
                    isOnboardingComplete: false,
                    intent: .chat,
                    milestones: OnboardingMilestones(
                        providerConnected: "2026-04-02T11:00:00Z",
                        firstOutcomeCompleted: nil,
                        profileBasicsSet: nil,
                        communicationStyleSet: nil,
                        secondaryTourSeen: nil
                    ),
                    permissions: OnboardingPermissions(
                        location: .notAsked,
                        notifications: .denied
                    ),
                    lastPromptedAt: nil
                )
            )
        ]
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .success(refreshedSettings)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            onboardingAPI: onboardingAPI,
            cache: TestCacheClient()
        )

        await viewModel.loadOnboarding()
        let success = await viewModel.savePrimaryProviderKey(
            provider: .anthropic,
            apiKey: "sk-test"
        )

        XCTAssertTrue(success)
        XCTAssertEqual(viewModel.onboardingState?.currentOnboardingStep, .featureDiscovery)
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .featureDiscovery)
    }

    func testSavePrimaryProviderKeyRefreshesOnboardingStateIntoFeatureDiscovery() async throws {
        let refreshedSettings = UserSettings(
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
            aiPrimaryProvider: "anthropic",
            aiPrimaryProviderHasKey: true,
            aiPrimaryProviderKeyLast4: "1234",
            enabledSkills: []
        )
        let onboardingAPI = MockOnboardingAPI()
        onboardingAPI.getResults = [
            .success(
                OnboardingState(
                    status: .dismissed,
                    providerReady: false,
                    currentOnboardingStep: .providerRecovery,
                    isOnboardingComplete: false,
                    intent: .chat,
                    milestones: OnboardingMilestones(
                        providerConnected: nil,
                        firstOutcomeCompleted: nil,
                        profileBasicsSet: nil,
                        communicationStyleSet: nil,
                        secondaryTourSeen: nil
                    ),
                    permissions: OnboardingPermissions(
                        location: .granted,
                        notifications: .granted
                    ),
                    lastPromptedAt: nil
                )
            ),
            .success(
                OnboardingState(
                    status: .dismissed,
                    providerReady: true,
                    currentOnboardingStep: .featureDiscovery,
                    isOnboardingComplete: false,
                    intent: .chat,
                    milestones: OnboardingMilestones(
                        providerConnected: "2026-04-02T11:00:00Z",
                        firstOutcomeCompleted: nil,
                        profileBasicsSet: nil,
                        communicationStyleSet: nil,
                        secondaryTourSeen: nil
                    ),
                    permissions: OnboardingPermissions(
                        location: .granted,
                        notifications: .granted
                    ),
                    lastPromptedAt: nil
                )
            )
        ]
        let viewModel = SettingsViewModel(
            settingsAPI: MockSettingsAPI(result: .success(refreshedSettings)),
            skillsAPI: MockSkillsAPI(result: .success(SkillsResponse(skills: []))),
            onboardingAPI: onboardingAPI,
            cache: TestCacheClient()
        )

        await viewModel.loadOnboarding()
        let success = await viewModel.savePrimaryProviderKey(
            provider: .anthropic,
            apiKey: "sk-test"
        )

        XCTAssertTrue(success)
        XCTAssertEqual(viewModel.onboardingState?.currentOnboardingStep, .featureDiscovery)
        XCTAssertEqual(viewModel.signedInOnboardingRecoveryState, .featureDiscovery)
    }

    func testDeletePrimaryProviderKeyUsesDisconnectIntent() async throws {
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
            aiPrimaryProvider: "google",
            aiPrimaryProviderHasKey: true,
            enabledSkills: []
        )
        let api = PrimaryProviderSettingsAPI(initial: initial)
        let viewModel = SettingsViewModel(
            settingsAPI: api,
            skillsAPI: PrimaryProviderEmptySkillsAPI(),
            cache: TestCacheClient()
        )

        await viewModel.load()
        await viewModel.deletePrimaryProviderKey(provider: .google)

        XCTAssertEqual(api.disconnectCallCount, 1)
        XCTAssertEqual(api.lastDisconnectProvider, "google")
        XCTAssertEqual(api.lastDisconnectSource, .aiProvider)
        XCTAssertNil(api.lastDisconnectSkillId)
    }

    private func encodedPayload(_ update: SettingsUpdate) throws -> [String: Any] {
        let data = try JSONEncoder().encode(update)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
