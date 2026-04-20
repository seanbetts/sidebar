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
        XCTAssertEqual(api.upsertedProviderKeys.count, 1)
        XCTAssertEqual(api.upsertedProviderKeys.first?.0, "anthropic")
        XCTAssertEqual(api.upsertedProviderKeys.first?.1, "anthropic-key")
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
        let store = SettingsWriteQueueExecutorStoreSpy()
        let payload = SettingsMutationPayload.profileImageUpload(
            assetRef: "asset-ref-1",
            contentType: "image/png",
            filename: "profile.png"
        )
        assetStore.stage(
            reference: "asset-ref-1",
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            contentType: "image/png",
            filename: "profile.png"
        )
        let api = SettingsWriteQueueExecutorAPISpy()
        let executor = SettingsWriteQueueExecutor(
            api: api,
            store: store,
            pendingSecretStore: secretStore,
            pendingAssetStore: assetStore
        )

        try await executor.execute(write: try queuedSettingsWrite(payload))

        XCTAssertEqual(assetStore.lookupReferences, ["asset-ref-1"])
        XCTAssertEqual(assetStore.deletedReferences, ["asset-ref-1"])
        XCTAssertEqual(api.uploadedProfileImages.count, 1)
        XCTAssertEqual(api.uploadedProfileImages.first?.data, Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(api.uploadedProfileImages.first?.contentType, "image/png")
        XCTAssertEqual(api.uploadedProfileImages.first?.filename, "profile.png")
        XCTAssertEqual(store.appliedProfileImageData, Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testExecuteProfileImageDeleteClearsLocallyCachedImage() async throws {
        let secretStore = SettingsPendingSecretStoreSpy()
        let assetStore = SettingsPendingAssetStoreSpy()
        let store = SettingsWriteQueueExecutorStoreSpy()
        let api = SettingsWriteQueueExecutorAPISpy()
        let executor = SettingsWriteQueueExecutor(
            api: api,
            store: store,
            pendingSecretStore: secretStore,
            pendingAssetStore: assetStore
        )

        try await executor.execute(write: try queuedSettingsWrite(.profileImageDelete))

        XCTAssertEqual(api.deleteProfileImageCallCount, 1)
        XCTAssertEqual(store.appliedProfileImageData, nil)
    }

    func testExecuteProviderKeyDisconnectRefreshesSettingsSnapshotWhenAvailable() async throws {
        let secretStore = SettingsPendingSecretStoreSpy()
        let assetStore = SettingsPendingAssetStoreSpy()
        let store = SettingsWriteQueueExecutorStoreSpy()
        let api = SettingsWriteQueueExecutorAPISpy(
            getSettingsResult: .success(
                makeUserSettings(
                    aiPrimaryProvider: nil,
                    enabledSkills: [],
                    installedStoreSkills: []
                )
            )
        )
        let executor = SettingsWriteQueueExecutor(
            api: api,
            store: store,
            pendingSecretStore: secretStore,
            pendingAssetStore: assetStore
        )
        let payload = SettingsMutationPayload.providerKeyDisconnect(
            provider: "openai",
            source: .skill,
            skillId: "planner"
        )

        try await executor.execute(write: try queuedSettingsWrite(payload))

        XCTAssertEqual(api.disconnectRequests.count, 1)
        XCTAssertEqual(api.disconnectRequests.first?.provider, "openai")
        XCTAssertEqual(api.disconnectRequests.first?.source, .skill)
        XCTAssertEqual(api.disconnectRequests.first?.skillId, "planner")
        XCTAssertEqual(store.appliedSettings?.enabledSkills, [])
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

@MainActor
private final class SettingsWriteQueueExecutorAPISpy: SettingsProviding {
    let getSettingsResult: Result<UserSettings, Error>
    private(set) var upsertedProviderKeys: [(String, String)] = []
    private(set) var updatedSettings: [SettingsUpdate] = []
    private(set) var updateSettingsCallCount = 0
    private(set) var uploadedProfileImages: [UploadedProfileImageRecord] = []
    private(set) var disconnectRequests: [DisconnectRequestRecord] = []
    private(set) var deleteProfileImageCallCount = 0

    init(
        getSettingsResult: Result<UserSettings, Error> = .failure(SettingsWriteQueueExecutorTestError.forced)
    ) {
        self.getSettingsResult = getSettingsResult
    }

    func getSettings() async throws -> UserSettings {
        try getSettingsResult.get()
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
        disconnectRequests.append(
            DisconnectRequestRecord(
                provider: provider,
                source: source,
                skillId: skillId
            )
        )
        return ProviderKeyDisconnectResponse(
            provider: provider,
            source: source,
            actions: ProviderKeyDisconnectActions(
                disabledSkillIds: source == .skill ? [skillId].compactMap { $0 } : [],
                detachedAIProvider: source == .aiProvider,
                deletedProviderKey: true
            ),
            remainingConsumers: ProviderKeyDisconnectRemainingConsumers(
                aiProvider: false,
                skillIds: []
            ),
            settings: ProviderKeyDisconnectSettings(
                enabledSkills: [],
                installedStoreSkills: [],
                aiPrimaryProvider: nil
            )
        )
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
        deleteProfileImageCallCount += 1
    }
}

@MainActor
private final class SettingsWriteQueueExecutorStoreSpy: SettingsWriteQueueApplying {
    private(set) var appliedSettings: UserSettings?
    private(set) var appliedProfileImageData: Data?

    func applySettings(_ settings: UserSettings, persist: Bool) {
        _ = persist
        appliedSettings = settings
    }

    func applyProfileImageData(_ data: Data?, persist: Bool) {
        _ = persist
        appliedProfileImageData = data
    }
}

@MainActor
private final class SettingsPendingSecretStoreSpy {
    private var secrets: [String: Data] = [:]
    private(set) var lookupReferences: [String] = []
    private(set) var deletedReferences: [String] = []

    func stage(_ secret: Data) throws -> String {
        let reference = UUID().uuidString
        stage(rawSecret: secret, reference: reference)
        return reference
    }

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

    func delete(reference: String) throws {
        deletedReferences.append(reference)
        secrets[reference] = nil
    }
}

extension SettingsPendingSecretStoreSpy: SettingsPendingSecretStoring {}

@MainActor
private final class SettingsPendingAssetStoreSpy {
    private var assets: [String: SettingsPendingAssetRecord] = [:]
    private(set) var lookupReferences: [String] = []
    private(set) var deletedReferences: [String] = []

    func stageProfileImage(data: Data, contentType: String, filename: String) throws -> String {
        let reference = UUID().uuidString
        stage(
            reference: reference,
            data: data,
            contentType: contentType,
            filename: filename
        )
        return reference
    }

    func stage(reference: String, data: Data, contentType: String, filename: String) {
        assets[reference] = SettingsPendingAssetRecord(
            data: data,
            contentType: contentType,
            filename: filename
        )
    }

    func lookup(reference: String) throws -> SettingsPendingAssetRecord {
        lookupReferences.append(reference)
        guard let asset = assets[reference] else {
            throw SettingsWriteQueueExecutorTestError.forced
        }
        return asset
    }

    func delete(reference: String) throws {
        deletedReferences.append(reference)
        assets[reference] = nil
    }
}

extension SettingsPendingAssetStoreSpy: SettingsPendingAssetStoring {}

private enum SettingsWriteQueueExecutorTestError: Error {
    case forced
}

private struct UploadedProfileImageRecord: Equatable {
    let data: Data
    let contentType: String
    let filename: String
}

private struct DisconnectRequestRecord: Equatable {
    let provider: String
    let source: ProviderKeyDisconnectSource
    let skillId: String?
}

private func makeUserSettings(
    name: String? = nil,
    jobTitle: String? = nil,
    employer: String? = nil,
    aiPrimaryProvider: String? = nil,
    enabledSkills: [String] = [],
    installedStoreSkills: [String] = []
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
        aiPrimaryProvider: aiPrimaryProvider,
        enabledSkills: enabledSkills,
        installedStoreSkills: installedStoreSkills
    )
}
