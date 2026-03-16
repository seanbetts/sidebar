import Foundation

@MainActor
extension SettingsViewModel {
    func applyAssistantSettingsUpdate(_ update: AssistantSettingsRealtimeUpdate) {
        guard let current = settings else {
            Task { [weak self] in
                await self?.load(force: true)
            }
            return
        }
        if update.requiresRefresh {
            Task { [weak self] in
                await self?.load(force: true)
            }
            return
        }

        let hasIdentity = update.assistantIdentity != nil || update.assistantIdentityMeta != nil
        let hasSoul = update.assistantSoul != nil || update.assistantSoulMeta != nil
        guard hasIdentity || hasSoul else {
            Task { [weak self] in
                await self?.load(force: true)
            }
            return
        }

        applySettingsResponse(
            UserSettings(
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
                assistantIdentity: update.assistantIdentity ?? current.assistantIdentity,
                assistantIdentityMeta: update.assistantIdentityMeta ?? current.assistantIdentityMeta,
                assistantSoul: update.assistantSoul ?? current.assistantSoul,
                assistantSoulMeta: update.assistantSoulMeta ?? current.assistantSoulMeta,
                aiPrimaryProvider: current.aiPrimaryProvider,
                aiPrimaryProviderHasKey: current.aiPrimaryProviderHasKey,
                aiPrimaryProviderKeyLast4: current.aiPrimaryProviderKeyLast4,
                enabledSkills: current.enabledSkills,
                installedStoreSkills: current.installedStoreSkills
            )
        )
    }
}
