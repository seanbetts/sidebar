import Foundation
import sideBarShared

@MainActor
/// Replays queued settings mutations against the settings API and local staging stores.
public final class SettingsWriteQueueExecutor: WriteQueueExecutor {
    private let api: any SettingsProviding
    private let store: (any SettingsWriteQueueApplying)?
    private let pendingSecretStore: any SettingsPendingSecretStoring
    private let pendingAssetStore: any SettingsPendingAssetStoring

    init(
        api: any SettingsProviding,
        store: (any SettingsWriteQueueApplying)? = nil,
        pendingSecretStore: any SettingsPendingSecretStoring,
        pendingAssetStore: any SettingsPendingAssetStoring
    ) {
        self.api = api
        self.store = store
        self.pendingSecretStore = pendingSecretStore
        self.pendingAssetStore = pendingAssetStore
    }

    func execute(write: PendingWriteRecord) async throws {
        let payload = try JSONDecoder().decode(SettingsMutationPayload.self, from: write.payload)
        switch payload.kind {
        case .settingsPatch:
            let response = try await api.updateSettings(payload.makeSettingsUpdate())
            store?.applySettings(response, persist: true)
        case .providerKeyUpsert:
            let secretRef = try requireSecretReference(from: payload)
            let apiKey = try pendingSecretStore.lookup(reference: secretRef)
            guard let apiKeyString = String(bytes: apiKey, encoding: .utf8) else {
                throw SettingsWriteQueueExecutorError.invalidSecretEncoding
            }
            _ = try await api.upsertProviderKey(
                provider: payload.provider ?? "",
                apiKey: apiKeyString
            )
            if payload.selectAsPrimaryProvider {
                let refreshed = try await api.updateSettings(
                    SettingsUpdate(aiPrimaryProvider: payload.provider)
                )
                store?.applySettings(refreshed, persist: true)
            }
            try pendingSecretStore.delete(reference: secretRef)
        case .profileImageUpload:
            let assetRef = try requireAssetReference(from: payload)
            let asset = try pendingAssetStore.lookup(reference: assetRef)
            try await api.uploadProfileImage(
                data: asset.data,
                contentType: payload.contentType ?? asset.contentType,
                filename: payload.filename ?? asset.filename
            )
            try pendingAssetStore.delete(reference: assetRef)
        }
    }

    private func requireSecretReference(from payload: SettingsMutationPayload) throws -> String {
        guard let reference = payload.rawSecretReference else {
            throw SettingsWriteQueueExecutorError.missingSecretReference
        }
        return reference
    }

    private func requireAssetReference(from payload: SettingsMutationPayload) throws -> String {
        guard let reference = payload.assetRef else {
            throw SettingsWriteQueueExecutorError.missingAssetReference
        }
        return reference
    }
}

private enum SettingsWriteQueueExecutorError: Error {
    case missingSecretReference
    case missingAssetReference
    case invalidSecretEncoding
}

private extension SettingsMutationPayload {
    func makeSettingsUpdate() -> SettingsUpdate {
        SettingsUpdate(
            communicationStyle: communicationStyle,
            workingRelationship: workingRelationship,
            name: name,
            jobTitle: jobTitle,
            employer: employer,
            dateOfBirth: dateOfBirth,
            gender: gender,
            pronouns: pronouns,
            location: location,
            notificationPreferences: notificationPreferences,
            assistantIdentity: assistantIdentity,
            aiPrimaryProvider: aiPrimaryProvider,
            enabledSkills: enabledSkills,
            includeDateOfBirth: includeDateOfBirth
        )
    }
}

protocol SettingsPendingSecretStoring: AnyObject {
    func lookup(reference: String) throws -> Data
    func delete(reference: String) throws
}

protocol SettingsPendingAssetStoring: AnyObject {
    func lookup(reference: String) throws -> SettingsPendingAssetRecord
    func delete(reference: String) throws
}

extension SettingsPendingSecretStore: SettingsPendingSecretStoring {}
extension SettingsPendingAssetStore: SettingsPendingAssetStoring {}
