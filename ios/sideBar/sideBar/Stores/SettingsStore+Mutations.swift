import Foundation
import sideBarShared

@MainActor
extension SettingsStore {
    public func commitUserPatch(_ patch: SettingsMutationPayload) async throws {
        guard let current = currentSnapshotForMutation() else {
            throw SettingsStoreError.missingCurrentSnapshot
        }
        guard let writeQueue else {
            throw SettingsStoreError.missingWriteQueue
        }

        let next = current.applying(patch: patch)
        apply(next, persist: true)

        try await writeQueue.enqueue(
            operation: .update,
            entityType: .settings,
            entityId: patch.entityId,
            payload: patch,
            serverSnapshot: nil
        )
    }
}

extension SettingsStore: SettingsWriteQueueApplying {
    func applySettings(_ settings: UserSettings, persist: Bool) {
        replace(settings, persist: persist)
    }
}

private extension UserSettings {
    func applying(patch: SettingsMutationPayload) -> UserSettings {
        let notificationPreferences = patch.notificationPreferences.map {
            self.notificationPreferences.applying(update: $0)
        } ?? notificationPreferences

        return UserSettings(
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
            assistantIdentity: patch.assistantIdentity ?? assistantIdentity,
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

private extension NotificationPreferencesSettings {
    func applying(update: NotificationPreferencesUpdate) -> NotificationPreferencesSettings {
        NotificationPreferencesSettings(
            taskRemindersEnabled: update.taskRemindersEnabled ?? taskRemindersEnabled,
            taskReminderTime: update.taskReminderTime ?? taskReminderTime,
            morningDigestEnabled: update.morningDigestEnabled ?? morningDigestEnabled,
            morningDigestTime: update.morningDigestTime ?? morningDigestTime,
            assistantReplyNotificationsEnabled:
                update.assistantReplyNotificationsEnabled ?? assistantReplyNotificationsEnabled,
            assistantProactiveNotificationsEnabled:
                update.assistantProactiveNotificationsEnabled ?? assistantProactiveNotificationsEnabled,
            scheduleTimezone: update.scheduleTimezone ?? scheduleTimezone
        )
    }
}
