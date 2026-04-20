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

        apply(current.applying(mutation: patch), persist: true)

        try await writeQueue.enqueue(
            operation: .update,
            entityType: .settings,
            entityId: patch.entityId,
            payload: patch,
            serverSnapshot: nil
        )
    }

    public func commitProviderKeyUpsert(
        provider: String,
        apiKey: String,
        selectAsPrimaryProvider: Bool
    ) async throws -> ProviderKeyStatusResponse {
        guard let current = currentSnapshotForMutation() else {
            throw SettingsStoreError.missingCurrentSnapshot
        }
        guard let writeQueue else {
            throw SettingsStoreError.missingWriteQueue
        }
        guard let pendingSecretStore else {
            throw SettingsStoreError.missingPendingSecretStore
        }

        let secretReference = try pendingSecretStore.stage(Data(apiKey.utf8))
        let keyLast4 = apiKey.isEmpty ? nil : String(apiKey.suffix(4))
        let payload = SettingsMutationPayload.providerKey(
            provider: provider,
            rawSecretReference: secretReference,
            providerKeyLast4: keyLast4,
            selectAsPrimaryProvider: selectAsPrimaryProvider
        )
        apply(current.applying(mutation: payload), persist: true)

        do {
            try await writeQueue.enqueue(
                operation: .update,
                entityType: .settings,
                entityId: payload.entityId,
                payload: payload,
                serverSnapshot: nil
            )
        } catch {
            try? pendingSecretStore.delete(reference: secretReference)
            throw error
        }

        return ProviderKeyStatusResponse(
            provider: provider,
            hasKey: true,
            keyLast4: keyLast4
        )
    }

    public func commitProviderKeyDelete(provider: String) async throws -> ProviderKeyStatusResponse {
        guard let current = currentSnapshotForMutation() else {
            throw SettingsStoreError.missingCurrentSnapshot
        }
        guard let writeQueue else {
            throw SettingsStoreError.missingWriteQueue
        }

        let payload = SettingsMutationPayload.providerKeyDelete(provider: provider)
        apply(current.applying(mutation: payload), persist: true)

        try await writeQueue.enqueue(
            operation: .update,
            entityType: .settings,
            entityId: payload.entityId,
            payload: payload,
            serverSnapshot: nil
        )

        let removedPrimaryProviderKey = current.aiPrimaryProvider == provider
        return ProviderKeyStatusResponse(
            provider: provider,
            hasKey: removedPrimaryProviderKey ? false : true,
            keyLast4: removedPrimaryProviderKey ? nil : current.aiPrimaryProviderKeyLast4
        )
    }

    public func commitProviderKeyDisconnect(
        provider: String,
        source: ProviderKeyDisconnectSource,
        skillId: String?
    ) async throws -> ProviderKeyDisconnectResponse {
        guard let current = currentSnapshotForMutation() else {
            throw SettingsStoreError.missingCurrentSnapshot
        }
        guard let writeQueue else {
            throw SettingsStoreError.missingWriteQueue
        }

        let payload = SettingsMutationPayload.providerKeyDisconnect(
            provider: provider,
            source: source,
            skillId: skillId
        )
        let next = current.applying(mutation: payload)
        apply(next, persist: true)

        try await writeQueue.enqueue(
            operation: .update,
            entityType: .settings,
            entityId: payload.entityId,
            payload: payload,
            serverSnapshot: nil
        )

        return ProviderKeyDisconnectResponse(
            provider: provider,
            source: source,
            actions: ProviderKeyDisconnectActions(
                disabledSkillIds: source == .skill ? [skillId].compactMap { $0 } : [],
                detachedAIProvider: source == .aiProvider && current.aiPrimaryProvider == provider,
                deletedProviderKey: source == .aiProvider && current.aiPrimaryProvider == provider
            ),
            remainingConsumers: ProviderKeyDisconnectRemainingConsumers(
                aiProvider: next.aiPrimaryProvider == provider,
                skillIds: []
            ),
            settings: ProviderKeyDisconnectSettings(
                enabledSkills: next.enabledSkills,
                installedStoreSkills: next.installedStoreSkills,
                aiPrimaryProvider: next.aiPrimaryProvider
            )
        )
    }

    public func commitProfileImageUpload(
        data: Data,
        contentType: String,
        filename: String
    ) async throws {
        guard let writeQueue else {
            throw SettingsStoreError.missingWriteQueue
        }
        guard let pendingAssetStore else {
            throw SettingsStoreError.missingPendingAssetStore
        }

        let assetReference = try pendingAssetStore.stageProfileImage(
            data: data,
            contentType: contentType,
            filename: filename
        )
        let payload = SettingsMutationPayload.profileImageUpload(
            assetRef: assetReference,
            contentType: contentType,
            filename: filename
        )
        applyProfileImageData(data, persist: true)

        do {
            try await writeQueue.enqueue(
                operation: .update,
                entityType: .settings,
                entityId: payload.entityId,
                payload: payload,
                serverSnapshot: nil
            )
        } catch {
            try? pendingAssetStore.delete(reference: assetReference)
            throw error
        }
    }

    public func commitProfileImageDelete() async throws {
        guard let writeQueue else {
            throw SettingsStoreError.missingWriteQueue
        }

        let payload = SettingsMutationPayload.profileImageDelete
        applyProfileImageData(nil, persist: true)

        try await writeQueue.enqueue(
            operation: .update,
            entityType: .settings,
            entityId: payload.entityId,
            payload: payload,
            serverSnapshot: nil
        )
    }
}

extension SettingsStore: SettingsWriteQueueApplying {
    func applySettings(_ settings: UserSettings, persist: Bool) {
        replace(settings, persist: persist)
    }

    func applyProfileImageData(_ data: Data?, persist: Bool) {
        if let current = currentSnapshotForMutation() {
            let next = current.replacingProfileImageURL(
                data == nil ? nil : (current.profileImageUrl?.trimmedOrNil ?? Self.pendingProfileImageURL)
            )
            apply(next, persist: persist)
        }

        if let data {
            cache.set(key: profileImageCacheKey, value: data, ttlSeconds: CachePolicy.profileImage)
        } else {
            cache.remove(key: profileImageCacheKey)
        }
    }
}

private extension UserSettings {
    func applying(mutation: SettingsMutationPayload) -> UserSettings {
        switch mutation.kind {
        case .settingsPatch:
            return applyingSettingsPatch(mutation)
        case .providerKeyUpsert:
            return applyingProviderKeyUpsert(mutation)
        case .providerKeyDelete:
            return applyingProviderKeyDelete(mutation)
        case .providerKeyDisconnect:
            return applyingProviderKeyDisconnect(mutation)
        case .profileImageUpload:
            return replacingProfileImageURL(profileImageUrl?.trimmedOrNil ?? SettingsStore.pendingProfileImageURL)
        case .profileImageDelete:
            return replacingProfileImageURL(nil)
        }
    }

    func replacingProfileImageURL(_ profileImageUrl: String?) -> UserSettings {
        UserSettings(
            userId: userId,
            communicationStyle: communicationStyle,
            workingRelationship: workingRelationship,
            name: name,
            jobTitle: jobTitle,
            employer: employer,
            dateOfBirth: dateOfBirth,
            gender: gender,
            pronouns: pronouns,
            location: location,
            profileImageUrl: profileImageUrl,
            notificationPreferences: notificationPreferences,
            assistantIdentity: assistantIdentity,
            assistantIdentityMeta: assistantIdentityMeta,
            assistantSoul: assistantSoul,
            assistantSoulMeta: assistantSoulMeta,
            aiPrimaryProvider: aiPrimaryProvider,
            aiPrimaryProviderHasKey: aiPrimaryProviderHasKey,
            aiPrimaryProviderKeyLast4: aiPrimaryProviderKeyLast4,
            enabledSkills: enabledSkills,
            installedStoreSkills: installedStoreSkills,
            canAccessInternalDiagnostics: canAccessInternalDiagnostics
        )
    }

    private func applyingSettingsPatch(_ patch: SettingsMutationPayload) -> UserSettings {
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

    private func applyingProviderKeyUpsert(_ mutation: SettingsMutationPayload) -> UserSettings {
        let nextPrimaryProvider = mutation.selectAsPrimaryProvider ? mutation.provider : aiPrimaryProvider
        let affectsPrimaryProvider = mutation.provider == nextPrimaryProvider && mutation.provider != nil
        return UserSettings(
            userId: userId,
            communicationStyle: communicationStyle,
            workingRelationship: workingRelationship,
            name: name,
            jobTitle: jobTitle,
            employer: employer,
            dateOfBirth: dateOfBirth,
            gender: gender,
            pronouns: pronouns,
            location: location,
            profileImageUrl: profileImageUrl,
            notificationPreferences: notificationPreferences,
            assistantIdentity: assistantIdentity,
            assistantIdentityMeta: assistantIdentityMeta,
            assistantSoul: assistantSoul,
            assistantSoulMeta: assistantSoulMeta,
            aiPrimaryProvider: nextPrimaryProvider,
            aiPrimaryProviderHasKey: affectsPrimaryProvider ? true : aiPrimaryProviderHasKey,
            aiPrimaryProviderKeyLast4: affectsPrimaryProvider ? mutation.providerKeyLast4 : aiPrimaryProviderKeyLast4,
            enabledSkills: enabledSkills,
            installedStoreSkills: installedStoreSkills,
            canAccessInternalDiagnostics: canAccessInternalDiagnostics
        )
    }

    private func applyingProviderKeyDelete(_ mutation: SettingsMutationPayload) -> UserSettings {
        guard aiPrimaryProvider == mutation.provider else {
            return self
        }
        return UserSettings(
            userId: userId,
            communicationStyle: communicationStyle,
            workingRelationship: workingRelationship,
            name: name,
            jobTitle: jobTitle,
            employer: employer,
            dateOfBirth: dateOfBirth,
            gender: gender,
            pronouns: pronouns,
            location: location,
            profileImageUrl: profileImageUrl,
            notificationPreferences: notificationPreferences,
            assistantIdentity: assistantIdentity,
            assistantIdentityMeta: assistantIdentityMeta,
            assistantSoul: assistantSoul,
            assistantSoulMeta: assistantSoulMeta,
            aiPrimaryProvider: aiPrimaryProvider,
            aiPrimaryProviderHasKey: false,
            aiPrimaryProviderKeyLast4: nil,
            enabledSkills: enabledSkills,
            installedStoreSkills: installedStoreSkills,
            canAccessInternalDiagnostics: canAccessInternalDiagnostics
        )
    }

    private func applyingProviderKeyDisconnect(_ mutation: SettingsMutationPayload) -> UserSettings {
        let shouldDetachPrimaryProvider = mutation.disconnectSource == .aiProvider && aiPrimaryProvider == mutation.provider
        let disconnectedSkillId = mutation.disconnectSource == .skill ? mutation.skillId : nil
        return UserSettings(
            userId: userId,
            communicationStyle: communicationStyle,
            workingRelationship: workingRelationship,
            name: name,
            jobTitle: jobTitle,
            employer: employer,
            dateOfBirth: dateOfBirth,
            gender: gender,
            pronouns: pronouns,
            location: location,
            profileImageUrl: profileImageUrl,
            notificationPreferences: notificationPreferences,
            assistantIdentity: assistantIdentity,
            assistantIdentityMeta: assistantIdentityMeta,
            assistantSoul: assistantSoul,
            assistantSoulMeta: assistantSoulMeta,
            aiPrimaryProvider: shouldDetachPrimaryProvider ? nil : aiPrimaryProvider,
            aiPrimaryProviderHasKey: shouldDetachPrimaryProvider ? false : aiPrimaryProviderHasKey,
            aiPrimaryProviderKeyLast4: shouldDetachPrimaryProvider ? nil : aiPrimaryProviderKeyLast4,
            enabledSkills: enabledSkills.filter { $0 != disconnectedSkillId },
            installedStoreSkills: installedStoreSkills.filter { $0 != disconnectedSkillId },
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

private extension SettingsStore {
    static let pendingProfileImageURL = "sidebar://settings/profile-image/pending"

    var profileImageCacheKey: String {
        cacheKey(for: CacheKeys.profileImage)
    }
}
