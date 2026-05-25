import Foundation
import sideBarShared

/// Replays queued settings mutations against the settings API and local staging stores.
@MainActor public final class SettingsWriteQueueExecutor: WriteQueueExecutor {
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
        case .providerKeyDelete:
            _ = try await api.deleteProviderKey(provider: payload.provider)
            if let refreshed = try? await api.getSettings() {
                store?.applySettings(refreshed, persist: true)
            }
        case .providerKeyDisconnect:
            _ = try await api.disconnectProviderConsumer(
                provider: payload.provider ?? "",
                source: payload.disconnectSource ?? .aiProvider,
                skillId: payload.skillId
            )
            if let refreshed = try? await api.getSettings() {
                store?.applySettings(refreshed, persist: true)
            }
        case .profileImageUpload:
            let assetRef = try requireAssetReference(from: payload)
            let asset = try pendingAssetStore.lookup(reference: assetRef)
            try await api.uploadProfileImage(
                data: asset.data,
                contentType: payload.contentType ?? asset.contentType,
                filename: payload.filename ?? asset.filename
            )
            store?.applyProfileImageData(asset.data, persist: true)
            try pendingAssetStore.delete(reference: assetRef)
        case .profileImageDelete:
            try await api.deleteProfileImage()
            store?.applyProfileImageData(nil, persist: true)
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

protocol SettingsPendingSecretStoring: AnyObject {
    func stage(_ secret: Data) throws -> String
    func lookup(reference: String) throws -> Data
    func delete(reference: String) throws
}

protocol SettingsPendingAssetStoring: AnyObject {
    func stageProfileImage(data: Data, contentType: String, filename: String) throws -> String
    func lookup(reference: String) throws -> SettingsPendingAssetRecord
    func delete(reference: String) throws
}

extension SettingsPendingSecretStore: SettingsPendingSecretStoring {}
extension SettingsPendingAssetStore: SettingsPendingAssetStoring {}
