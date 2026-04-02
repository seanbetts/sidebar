import Foundation
import sideBarShared
@testable import sideBar

final class PrimaryProviderSettingsAPI: SettingsProviding {
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

struct PrimaryProviderEmptySkillsAPI: SkillsProviding {
    func list() async throws -> SkillsResponse {
        SkillsResponse(skills: [])
    }
}
