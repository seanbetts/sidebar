import Foundation
import sideBarShared

extension SettingsStore {
    func apply(_ settings: UserSettings, persist: Bool) {
        self.settings = settings
        guard persist else {
            return
        }

        cache.set(key: cacheKey, value: settings, ttlSeconds: CachePolicy.userSettings)
        offlineStore?.set(
            key: cacheKey,
            entityType: "settings",
            value: settings,
            lastSyncAt: offlineStore?.lastSyncAt(for: cacheKey)
        )
    }
}

extension UserSettings {
    func applying(patch: SettingsMutationPayload) -> UserSettings {
        UserSettings(
            userId: userId,
            communicationStyle: patch.communicationStyle ?? communicationStyle,
            workingRelationship: patch.workingRelationship ?? workingRelationship,
            name: patch.name ?? name,
            jobTitle: patch.jobTitle ?? jobTitle,
            employer: patch.employer ?? employer,
            dateOfBirth: patch.includeDateOfBirth ? patch.dateOfBirth : dateOfBirth,
            gender: patch.gender ?? gender,
            pronouns: patch.pronouns ?? pronouns,
            location: patch.location ?? location,
            profileImageUrl: profileImageUrl,
            notificationPreferences: notificationPreferences,
            assistantIdentity: assistantIdentity,
            assistantIdentityMeta: assistantIdentityMeta,
            assistantSoul: assistantSoul,
            assistantSoulMeta: assistantSoulMeta,
            aiPrimaryProvider: patch.aiPrimaryProvider ?? aiPrimaryProvider,
            aiPrimaryProviderHasKey: aiPrimaryProviderHasKey,
            aiPrimaryProviderKeyLast4: aiPrimaryProviderKeyLast4,
            enabledSkills: patch.enabledSkills ?? enabledSkills,
            installedStoreSkills: installedStoreSkills,
            canAccessInternalDiagnostics: canAccessInternalDiagnostics
        )
    }
}
