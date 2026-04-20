import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class SettingsWriteQueueExecutorTests: XCTestCase {
    func testExecuteProviderKeyMutationLoadsRawSecretFromPendingSecretStoreAndDeletesIt() async throws {
        let secretStore = SettingsPendingSecretStoreSpy()
        let api = SettingsWriteQueueExecutorAPISpy()
        let assetStore = SettingsPendingAssetStoreSpy()
        let executor = SettingsWriteQueueExecutor(
            api: api,
            pendingSecretStore: secretStore,
            pendingAssetStore: assetStore
        )
        let payload = SettingsMutationPayload.providerKey(
            provider: "anthropic",
            rawSecretReference: "secret-ref-1"
        )
        secretStore.stage(rawSecret: Data("anthropic-key".utf8), reference: "secret-ref-1")

        try await executor.execute(write: try queuedSettingsWrite(payload))

        XCTAssertEqual(secretStore.lookupReferences, ["secret-ref-1"])
        XCTAssertEqual(secretStore.deletedReferences, ["secret-ref-1"])
        XCTAssertEqual(api.upsertedProviderKeys, [("anthropic", "anthropic-key")])
    }

    func testExecuteSettingsPatchReplaysDecodedMutationIntoUpdateSettings() async throws {
        let secretStore = SettingsPendingSecretStoreSpy()
        let assetStore = SettingsPendingAssetStoreSpy()
        let api = SettingsWriteQueueExecutorAPISpy()
        let executor = SettingsWriteQueueExecutor(
            api: api,
            pendingSecretStore: secretStore,
            pendingAssetStore: assetStore
        )
        let payload = SettingsMutationPayload(
            name: "Ada Lovelace",
            jobTitle: "Mathematician",
            employer: "Analytical Engine"
        )

        try await executor.execute(write: try queuedSettingsWrite(payload))

        XCTAssertEqual(api.updateSettingsCallCount, 1)
        XCTAssertEqual(api.updatedSettings.last?.name, "Ada Lovelace")
        XCTAssertEqual(api.updatedSettings.last?.jobTitle, "Mathematician")
        XCTAssertEqual(api.updatedSettings.last?.employer, "Analytical Engine")
        XCTAssertTrue(api.uploadedProfileImages.isEmpty)
    }

    func testExecuteProfileImageReferenceReplaysStagedAssetIntoUploadProfileImage() async throws {
        let secretStore = SettingsPendingSecretStoreSpy()
        let assetStore = SettingsPendingAssetStoreSpy()
        assetStore.stage(
            reference: "asset-ref-1",
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            contentType: "image/png",
            filename: "profile.png"
        )
        let api = SettingsWriteQueueExecutorAPISpy()
        let executor = SettingsWriteQueueExecutor(
            api: api,
            pendingSecretStore: secretStore,
            pendingAssetStore: assetStore
        )

        try await executor.execute(write: try queuedProfileImageReferenceWrite(reference: "asset-ref-1"))

        XCTAssertEqual(assetStore.lookupReferences, ["asset-ref-1"])
        XCTAssertEqual(assetStore.deletedReferences, ["asset-ref-1"])
        XCTAssertEqual(api.uploadedProfileImages.count, 1)
        XCTAssertEqual(api.uploadedProfileImages.first?.data, Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(api.uploadedProfileImages.first?.contentType, "image/png")
        XCTAssertEqual(api.uploadedProfileImages.first?.filename, "profile.png")
    }
}

private func queuedSettingsWrite(_ payload: SettingsMutationPayload) throws -> PendingWriteRecord {
    let payloadData = try JSONEncoder().encode(payload)
    return PendingWriteRecord(
        id: UUID(),
        operationType: WriteOperation.update.rawValue,
        entityType: WriteEntityType.settings.rawValue,
        entityId: payload.entityId,
        payload: payloadData,
        serverSnapshot: nil,
        attempts: 0
    )
}

private func queuedProfileImageReferenceWrite(reference: String) throws -> PendingWriteRecord {
    let payload = ProfileImageReferenceWritePayload(reference: reference)
    let payloadData = try JSONEncoder().encode(payload)
    return PendingWriteRecord(
        id: UUID(),
        operationType: WriteOperation.update.rawValue,
        entityType: WriteEntityType.settings.rawValue,
        entityId: "profile-image",
        payload: payloadData,
        serverSnapshot: nil,
        attempts: 0
    )
}

private struct ProfileImageReferenceWritePayload: Codable, Equatable {
    let reference: String
}

@MainActor
private final class SettingsWriteQueueExecutorAPISpy: SettingsProviding {
    private(set) var upsertedProviderKeys: [(String, String)] = []
    private(set) var updatedSettings: [SettingsUpdate] = []
    private(set) var updateSettingsCallCount = 0
    private(set) var uploadedProfileImages: [UploadedProfileImageRecord] = []

    func getSettings() async throws -> UserSettings {
        throw SettingsWriteQueueExecutorTestError.forced
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        updateSettingsCallCount += 1
        updatedSettings.append(update)
        return makeUserSettings(
            name: update.name,
            jobTitle: update.jobTitle,
            employer: update.employer
        )
    }

    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        return ProviderKeyStatusResponse(provider: nil, hasKey: false, keyLast4: nil)
    }

    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        upsertedProviderKeys.append((provider, apiKey))
        return ProviderKeyStatusResponse(provider: provider, hasKey: true, keyLast4: "1234")
    }

    func deleteProviderKey(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        return ProviderKeyStatusResponse(provider: nil, hasKey: false, keyLast4: nil)
    }

    func disconnectProviderConsumer(
        provider: String,
        source: ProviderKeyDisconnectSource,
        skillId: String?
    ) async throws -> ProviderKeyDisconnectResponse {
        _ = provider
        _ = source
        _ = skillId
        throw SettingsWriteQueueExecutorTestError.forced
    }

    func getShortcutsToken() async throws -> ShortcutsTokenResponse {
        throw SettingsWriteQueueExecutorTestError.forced
    }

    func rotateShortcutsToken() async throws -> ShortcutsTokenResponse {
        throw SettingsWriteQueueExecutorTestError.forced
    }

    func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        uploadedProfileImages.append(
            UploadedProfileImageRecord(
                data: data,
                contentType: contentType,
                filename: filename
            )
        )
    }

    func getProfileImage() async throws -> Data {
        throw SettingsWriteQueueExecutorTestError.forced
    }

    func deleteProfileImage() async throws {
        throw SettingsWriteQueueExecutorTestError.forced
    }
}

@MainActor
private final class SettingsPendingSecretStoreSpy {
    private var secrets: [String: Data] = [:]
    private(set) var lookupReferences: [String] = []
    private(set) var deletedReferences: [String] = []

    func stage(rawSecret: Data, reference: String) {
        secrets[reference] = rawSecret
    }

    func lookup(reference: String) throws -> Data {
        lookupReferences.append(reference)
        guard let secret = secrets[reference] else {
            throw SettingsWriteQueueExecutorTestError.forced
        }
        return secret
    }

    func delete(reference: String) {
        deletedReferences.append(reference)
        secrets[reference] = nil
    }
}

@MainActor
private final class SettingsPendingAssetStoreSpy {
    private var assets: [String: StagedAssetRecord] = [:]
    private(set) var lookupReferences: [String] = []
    private(set) var deletedReferences: [String] = []

    func stage(reference: String, data: Data, contentType: String, filename: String) {
        assets[reference] = StagedAssetRecord(
            data: data,
            contentType: contentType,
            filename: filename
        )
    }

    func lookup(reference: String) throws -> StagedAssetRecord {
        lookupReferences.append(reference)
        guard let asset = assets[reference] else {
            throw SettingsWriteQueueExecutorTestError.forced
        }
        return asset
    }

    func delete(reference: String) {
        deletedReferences.append(reference)
        assets[reference] = nil
    }
}

private enum SettingsWriteQueueExecutorTestError: Error {
    case forced
}

private struct UploadedProfileImageRecord: Equatable {
    let data: Data
    let contentType: String
    let filename: String
}

private struct StagedAssetRecord: Equatable {
    let data: Data
    let contentType: String
    let filename: String
}

private func makeUserSettings(
    name: String? = nil,
    jobTitle: String? = nil,
    employer: String? = nil
) -> UserSettings {
    UserSettings(
        userId: "user-1",
        communicationStyle: nil,
        workingRelationship: nil,
        name: name,
        jobTitle: jobTitle,
        employer: employer,
        dateOfBirth: nil,
        gender: nil,
        pronouns: nil,
        location: nil,
        profileImageUrl: nil,
        enabledSkills: []
    )
}
