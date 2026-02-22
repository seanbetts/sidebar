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
            apiKey: "test-google-key"
        )

        XCTAssertTrue(success)
        XCTAssertEqual(api.upsertCallCount, 1)
        XCTAssertEqual(api.lastUpsertProvider, "google")
        XCTAssertEqual(api.lastUpsertApiKey, "test-google-key")
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

private final class PrimaryProviderSettingsAPI: SettingsProviding {
    var current: UserSettings
    var updateCallCount = 0
    var lastUpdate: SettingsUpdate?
    var upsertCallCount = 0
    var lastUpsertProvider: String?
    var lastUpsertApiKey: String?
    var disconnectCallCount = 0
    var lastDisconnectProvider: String?
    var lastDisconnectSource: ProviderKeyDisconnectSource?
    var lastDisconnectSkillId: String?

    init(initial: UserSettings) {
        current = initial
    }

    func getSettings() async throws -> UserSettings {
        current
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        updateCallCount += 1
        lastUpdate = update
        let provider = update.aiPrimaryProvider ?? current.aiPrimaryProvider
        current = UserSettings(
            userId: current.userId,
            communicationStyle: current.communicationStyle,
            workingRelationship: current.workingRelationship,
            name: current.name,
            jobTitle: current.jobTitle,
            employer: current.employer,
            dateOfBirth: current.dateOfBirth,
            gender: current.gender,
            pronouns: current.pronouns,
            location: current.location,
            profileImageUrl: current.profileImageUrl,
            assistantIdentity: current.assistantIdentity,
            assistantIdentityMeta: current.assistantIdentityMeta,
            assistantSoul: current.assistantSoul,
            assistantSoulMeta: current.assistantSoulMeta,
            aiPrimaryProvider: provider,
            aiPrimaryProviderHasKey: current.aiPrimaryProviderHasKey,
            aiPrimaryProviderKeyLast4: current.aiPrimaryProviderKeyLast4,
            enabledSkills: current.enabledSkills
        )
        return current
    }

    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        ProviderKeyStatusResponse(
            provider: provider,
            hasKey: current.aiPrimaryProviderHasKey,
            keyLast4: current.aiPrimaryProviderKeyLast4
        )
    }

    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        upsertCallCount += 1
        lastUpsertProvider = provider
        lastUpsertApiKey = apiKey
        let suffix = String(apiKey.suffix(4))
        current = UserSettings(
            userId: current.userId,
            communicationStyle: current.communicationStyle,
            workingRelationship: current.workingRelationship,
            name: current.name,
            jobTitle: current.jobTitle,
            employer: current.employer,
            dateOfBirth: current.dateOfBirth,
            gender: current.gender,
            pronouns: current.pronouns,
            location: current.location,
            profileImageUrl: current.profileImageUrl,
            assistantIdentity: current.assistantIdentity,
            assistantIdentityMeta: current.assistantIdentityMeta,
            assistantSoul: current.assistantSoul,
            assistantSoulMeta: current.assistantSoulMeta,
            aiPrimaryProvider: current.aiPrimaryProvider,
            aiPrimaryProviderHasKey: true,
            aiPrimaryProviderKeyLast4: suffix,
            enabledSkills: current.enabledSkills
        )
        return ProviderKeyStatusResponse(provider: provider, hasKey: true, keyLast4: suffix)
    }

    func deleteProviderKey(provider: String?) async throws -> ProviderKeyStatusResponse {
        current = UserSettings(
            userId: current.userId,
            communicationStyle: current.communicationStyle,
            workingRelationship: current.workingRelationship,
            name: current.name,
            jobTitle: current.jobTitle,
            employer: current.employer,
            dateOfBirth: current.dateOfBirth,
            gender: current.gender,
            pronouns: current.pronouns,
            location: current.location,
            profileImageUrl: current.profileImageUrl,
            assistantIdentity: current.assistantIdentity,
            assistantIdentityMeta: current.assistantIdentityMeta,
            assistantSoul: current.assistantSoul,
            assistantSoulMeta: current.assistantSoulMeta,
            aiPrimaryProvider: current.aiPrimaryProvider,
            aiPrimaryProviderHasKey: false,
            aiPrimaryProviderKeyLast4: nil,
            enabledSkills: current.enabledSkills
        )
        return ProviderKeyStatusResponse(provider: provider, hasKey: false, keyLast4: nil)
    }

    func disconnectProviderConsumer(
        provider: String,
        source: ProviderKeyDisconnectSource,
        skillId: String?
    ) async throws -> ProviderKeyDisconnectResponse {
        disconnectCallCount += 1
        lastDisconnectProvider = provider
        lastDisconnectSource = source
        lastDisconnectSkillId = skillId

        let shouldDetachAIProvider = source == .aiProvider && current.aiPrimaryProvider == provider
        current = UserSettings(
            userId: current.userId,
            communicationStyle: current.communicationStyle,
            workingRelationship: current.workingRelationship,
            name: current.name,
            jobTitle: current.jobTitle,
            employer: current.employer,
            dateOfBirth: current.dateOfBirth,
            gender: current.gender,
            pronouns: current.pronouns,
            location: current.location,
            profileImageUrl: current.profileImageUrl,
            assistantIdentity: current.assistantIdentity,
            assistantIdentityMeta: current.assistantIdentityMeta,
            assistantSoul: current.assistantSoul,
            assistantSoulMeta: current.assistantSoulMeta,
            aiPrimaryProvider: shouldDetachAIProvider ? nil : current.aiPrimaryProvider,
            aiPrimaryProviderHasKey: false,
            aiPrimaryProviderKeyLast4: nil,
            enabledSkills: current.enabledSkills,
            installedStoreSkills: current.installedStoreSkills
        )

        return ProviderKeyDisconnectResponse(
            provider: provider,
            source: source,
            actions: ProviderKeyDisconnectActions(
                disabledSkillIds: source == .skill ? [skillId].compactMap { $0 } : [],
                detachedAIProvider: shouldDetachAIProvider,
                deletedProviderKey: true
            ),
            remainingConsumers: ProviderKeyDisconnectRemainingConsumers(
                aiProvider: current.aiPrimaryProvider == provider,
                skillIds: []
            ),
            settings: ProviderKeyDisconnectSettings(
                enabledSkills: current.enabledSkills,
                installedStoreSkills: current.installedStoreSkills,
                aiPrimaryProvider: current.aiPrimaryProvider
            )
        )
    }

    func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        ShortcutsTokenResponse(token: "")
    }

    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        ShortcutsTokenResponse(token: "")
    }

    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        _ = data
        _ = contentType
        _ = filename
    }

    func getProfileImage() async throws -> Data {
        Data()
    }

    func deleteProfileImage() async throws {
    }
}

private struct PrimaryProviderEmptySkillsAPI: SkillsProviding {
    func list() async throws -> SkillsResponse {
        SkillsResponse(skills: [])
    }
}
