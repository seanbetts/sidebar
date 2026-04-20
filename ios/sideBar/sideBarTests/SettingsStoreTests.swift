import CoreData
import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testLoadPrefersOfflineSnapshotWhenServerReadFails() async throws {
        let cachedSettings = makeSettings(name: "Stale cache snapshot")
        let offlineSnapshot = makeSettings(name: "Offline snapshot")
        let persistence = PersistenceController(inMemory: true)
        let cache = SettingsPersistenceSpy()
        cache.stage(key: CacheKeys.userSettings, value: cachedSettings)
        let offlineStore = OfflineStore(container: persistence.container)
        offlineStore.set(
            key: CacheKeys.userSettings,
            entityType: "settings",
            value: offlineSnapshot,
            lastSyncAt: nil
        )
        let api = SettingsStoreAPISpy(
            getSettingsResult: .failure(SettingsStoreTestError.forced)
        )
        let writeQueue = SettingsWriteQueueSpy()
        let store = SettingsStore(
            settingsAPI: api,
            cache: cache,
            offlineStore: offlineStore,
            writeQueue: writeQueue
        )

        let loaded = try await store.load()

        XCTAssertEqual(loaded.userId, offlineSnapshot.userId)
        XCTAssertEqual(loaded.name, offlineSnapshot.name)
        XCTAssertEqual(loaded.jobTitle, offlineSnapshot.jobTitle)
        XCTAssertEqual(loaded.enabledSkills, offlineSnapshot.enabledSkills)
        XCTAssertEqual(store.settings?.userId, offlineSnapshot.userId)
        XCTAssertEqual(store.settings?.name, offlineSnapshot.name)
        XCTAssertEqual(store.settings?.jobTitle, offlineSnapshot.jobTitle)
        XCTAssertEqual(store.settings?.enabledSkills, offlineSnapshot.enabledSkills)
        let cachedSnapshot: UserSettings? = try cache.snapshot(for: CacheKeys.userSettings)
        XCTAssertEqual(cachedSnapshot?.name, cachedSettings.name)
        let persistedOffline: UserSettings? = offlineStore.get(
            key: CacheKeys.userSettings,
            as: UserSettings.self
        )
        XCTAssertEqual(persistedOffline?.name, offlineSnapshot.name)
        XCTAssertEqual(api.getSettingsCallCount, 1)
        XCTAssertEqual(writeQueue.enqueuedWrites.count, 0)
    }

    func testCommitUserPatchUpdatesLocalSnapshotAndEnqueuesSettingsWrite() async throws {
        let initialSettings = makeSettings(name: "Initial")
        let persistence = PersistenceController(inMemory: true)
        let cache = SettingsPersistenceSpy()
        cache.stage(key: CacheKeys.userSettings, value: initialSettings)
        let offlineStore = OfflineStore(container: persistence.container)
        offlineStore.set(
            key: CacheKeys.userSettings,
            entityType: "settings",
            value: initialSettings,
            lastSyncAt: nil
        )
        let api = SettingsStoreAPISpy(
            getSettingsResult: .success(initialSettings),
            updateSettingsResult: .success(initialSettings)
        )
        let writeQueue = SettingsWriteQueueSpy()
        let store = SettingsStore(
            settingsAPI: api,
            cache: cache,
            offlineStore: offlineStore,
            writeQueue: writeQueue
        )
        let patch = SettingsMutationPayload(
            name: "Ada Lovelace",
            notificationPreferences: NotificationPreferencesUpdate(
                taskRemindersEnabled: true,
                assistantReplyNotificationsEnabled: false
            ),
            assistantIdentity: AssistantIdentitySettings(
                name: "Ada",
                tone: "Warm",
                values: "Precision",
                boundaries: "No fluff"
            )
        )

        try await store.commitUserPatch(patch)

        XCTAssertEqual(store.settings?.name, "Ada Lovelace")
        XCTAssertEqual(store.settings?.notificationPreferences.taskRemindersEnabled, true)
        XCTAssertEqual(store.settings?.notificationPreferences.assistantReplyNotificationsEnabled, false)
        XCTAssertEqual(store.settings?.assistantIdentity?.name, "Ada")
        XCTAssertEqual(store.settings?.assistantIdentity?.tone, "Warm")
        XCTAssertEqual(cache.setCallCount, 1)
        let updatedCacheSnapshot: UserSettings? = try cache.snapshot(for: CacheKeys.userSettings)
        XCTAssertEqual(updatedCacheSnapshot?.name, "Ada Lovelace")
        XCTAssertEqual(updatedCacheSnapshot?.notificationPreferences.taskRemindersEnabled, true)
        XCTAssertEqual(updatedCacheSnapshot?.assistantIdentity?.values, "Precision")
        let persistedOffline: UserSettings? = offlineStore.get(
            key: CacheKeys.userSettings,
            as: UserSettings.self
        )
        XCTAssertEqual(persistedOffline?.name, "Ada Lovelace")
        XCTAssertEqual(persistedOffline?.notificationPreferences.taskRemindersEnabled, true)
        XCTAssertEqual(persistedOffline?.assistantIdentity?.boundaries, "No fluff")
        XCTAssertEqual(writeQueue.enqueuedWrites.count, 1)
        let enqueuedWrite = try XCTUnwrap(writeQueue.enqueuedWrites.first)
        XCTAssertEqual(enqueuedWrite.operationType, WriteOperation.update.rawValue)
        XCTAssertEqual(enqueuedWrite.entityType, WriteEntityType.settings.rawValue)
        XCTAssertEqual(enqueuedWrite.entityId, patch.entityId)
        let decodedPayload = try JSONDecoder().decode(SettingsMutationPayload.self, from: enqueuedWrite.payload)
        XCTAssertEqual(decodedPayload.name, patch.name)
        XCTAssertEqual(decodedPayload.notificationPreferences, patch.notificationPreferences)
        XCTAssertEqual(decodedPayload.assistantIdentity, patch.assistantIdentity)
        XCTAssertEqual(api.updateSettingsCallCount, 0)
    }

    func testCommitProviderKeyUpsertStagesSecretAndEnqueuesQueueSafeMutation() async throws {
        let initialSettings = makeSettings(name: "Initial")
        let persistence = PersistenceController(inMemory: true)
        let cache = SettingsPersistenceSpy()
        let secretStore = SettingsPendingSecretStore(useInMemoryStore: true)
        let api = SettingsStoreAPISpy(getSettingsResult: .success(initialSettings))
        let writeQueue = SettingsWriteQueueSpy()
        let store = SettingsStore(
            settingsAPI: api,
            cache: cache,
            offlineStore: OfflineStore(container: persistence.container),
            pendingSecretStore: secretStore,
            writeQueue: writeQueue
        )
        store.replace(initialSettings, persist: true)

        let status = try await store.commitProviderKeyUpsert(
            provider: "openai",
            apiKey: "sk-openai-1234",
            selectAsPrimaryProvider: true
        )

        XCTAssertEqual(status.provider, "openai")
        XCTAssertTrue(status.hasKey)
        XCTAssertEqual(status.keyLast4, "1234")
        XCTAssertEqual(store.settings?.aiPrimaryProvider, "openai")
        XCTAssertTrue(store.settings?.aiPrimaryProviderHasKey == true)
        XCTAssertEqual(store.settings?.aiPrimaryProviderKeyLast4, "1234")
        XCTAssertEqual(writeQueue.enqueuedWrites.count, 1)
        let queuedWrite = try XCTUnwrap(writeQueue.enqueuedWrites.first)
        let payload = try JSONDecoder().decode(SettingsMutationPayload.self, from: queuedWrite.payload)
        XCTAssertEqual(payload.kind, .providerKeyUpsert)
        XCTAssertEqual(payload.provider, "openai")
        XCTAssertEqual(payload.providerKeyLast4, "1234")
        XCTAssertTrue(payload.selectAsPrimaryProvider)
        let secretReference = try XCTUnwrap(payload.rawSecretReference)
        XCTAssertEqual(try secretStore.lookup(reference: secretReference), Data("sk-openai-1234".utf8))
        XCTAssertEqual(api.updateSettingsCallCount, 0)
    }

    func testCommitProfileImageUploadCachesDataAndEnqueuesAssetReference() async throws {
        let initialSettings = makeSettings(name: "Initial")
        let persistence = PersistenceController(inMemory: true)
        let cache = SettingsPersistenceSpy()
        let assetRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let assetStore = SettingsPendingAssetStore(
            fileManager: .default,
            rootDirectory: assetRoot
        )
        let api = SettingsStoreAPISpy(getSettingsResult: .success(initialSettings))
        let writeQueue = SettingsWriteQueueSpy()
        let store = SettingsStore(
            settingsAPI: api,
            cache: cache,
            offlineStore: OfflineStore(container: persistence.container),
            pendingAssetStore: assetStore,
            writeQueue: writeQueue
        )
        store.replace(initialSettings, persist: true)

        try await store.commitProfileImageUpload(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            contentType: "image/png",
            filename: "profile.png"
        )

        XCTAssertEqual(writeQueue.enqueuedWrites.count, 1)
        let queuedWrite = try XCTUnwrap(writeQueue.enqueuedWrites.first)
        let payload = try JSONDecoder().decode(SettingsMutationPayload.self, from: queuedWrite.payload)
        XCTAssertEqual(payload.kind, .profileImageUpload)
        XCTAssertEqual(queuedWrite.entityId, "profile-image")
        let assetReference = try XCTUnwrap(payload.assetRef)
        let stagedAsset = try assetStore.lookup(reference: assetReference)
        XCTAssertEqual(stagedAsset.data, Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(stagedAsset.contentType, "image/png")
        XCTAssertEqual(stagedAsset.filename, "profile.png")
        XCTAssertEqual(store.settings?.profileImageUrl, "sidebar://settings/profile-image/pending")
        let cachedImage: Data? = try cache.snapshot(for: CacheKeys.profileImage)
        XCTAssertEqual(cachedImage, Data([0x89, 0x50, 0x4E, 0x47]))
    }
}

private func makeSettings(
    name: String?,
    profileImageUrl: String? = nil,
    aiPrimaryProvider: String? = nil,
    aiPrimaryProviderHasKey: Bool = false,
    aiPrimaryProviderKeyLast4: String? = nil
) -> UserSettings {
    UserSettings(
        userId: "user-1",
        communicationStyle: nil,
        workingRelationship: nil,
        name: name,
        jobTitle: nil,
        employer: nil,
        dateOfBirth: nil,
        gender: nil,
        pronouns: nil,
        location: nil,
        profileImageUrl: profileImageUrl,
        aiPrimaryProvider: aiPrimaryProvider,
        aiPrimaryProviderHasKey: aiPrimaryProviderHasKey,
        aiPrimaryProviderKeyLast4: aiPrimaryProviderKeyLast4,
        enabledSkills: []
    )
}

private enum SettingsStoreTestError: Error {
    case forced
}

@MainActor
private final class SettingsPersistenceSpy: CacheClient {
    private var snapshots: [String: Data] = [:]
    private(set) var setCallCount = 0
    private(set) var lastSetKeys: [String] = []

    func stage<T: Codable>(key: String, value: T) {
        snapshots[key] = try? JSONEncoder().encode(value)
    }

    func get<T: Codable>(key: String) -> T? {
        guard let data = snapshots[key] else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func setEncoded(key: String, payload data: Data, typeName: String, ttlSeconds: TimeInterval) {
        _ = typeName
        _ = ttlSeconds
        setCallCount += 1
        lastSetKeys.append(key)
        snapshots[key] = data
    }

    func remove(key: String) {
        snapshots[key] = nil
    }

    func clear() {
        snapshots.removeAll()
    }

    func snapshot<T: Decodable>(for key: String, as type: T.Type = T.self) throws -> T? {
        guard let data = snapshots[key] else {
            return nil
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

@MainActor
private final class SettingsStoreAPISpy: SettingsProviding {
    let getSettingsResult: Result<UserSettings, Error>
    let updateSettingsResult: Result<UserSettings, Error>
    private(set) var getSettingsCallCount = 0
    private(set) var updateSettingsCallCount = 0

    init(
        getSettingsResult: Result<UserSettings, Error>,
        updateSettingsResult: Result<UserSettings, Error> = .failure(SettingsStoreTestError.forced)
    ) {
        self.getSettingsResult = getSettingsResult
        self.updateSettingsResult = updateSettingsResult
    }

    func getSettings() async throws -> UserSettings {
        getSettingsCallCount += 1
        return try getSettingsResult.get()
    }

    func updateSettings(_ update: SettingsUpdate) async throws -> UserSettings {
        updateSettingsCallCount += 1
        _ = update
        return try updateSettingsResult.get()
    }

    func getProviderKeyStatus(provider: String?) async throws -> ProviderKeyStatusResponse {
        _ = provider
        return ProviderKeyStatusResponse(provider: nil, hasKey: false, keyLast4: nil)
    }

    func upsertProviderKey(provider: String, apiKey: String) async throws -> ProviderKeyStatusResponse {
        _ = provider
        _ = apiKey
        return ProviderKeyStatusResponse(provider: nil, hasKey: false, keyLast4: nil)
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
        return ProviderKeyDisconnectResponse(
            provider: "",
            source: .skill,
            actions: ProviderKeyDisconnectActions(
                disabledSkillIds: [],
                detachedAIProvider: false,
                deletedProviderKey: false
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

@MainActor
private final class SettingsWriteQueueSpy {
    private(set) var enqueuedWrites: [PendingWriteRecord] = []

    func enqueue<T: Encodable>(
        operation: WriteOperation,
        entityType: WriteEntityType,
        entityId: String?,
        payload: T,
        serverSnapshot: ServerSnapshot?
    ) async throws {
        _ = serverSnapshot
        let encodedPayload = try JSONEncoder().encode(payload)
        enqueuedWrites.append(
            PendingWriteRecord(
                id: UUID(),
                operationType: operation.rawValue,
                entityType: entityType.rawValue,
                entityId: entityId,
                payload: encodedPayload,
                serverSnapshot: nil,
                attempts: 0
            )
        )
    }

    func enqueue(_ write: PendingWriteRecord) async throws {
        enqueuedWrites.append(write)
    }
}

extension SettingsWriteQueueSpy: SettingsWriteQueueEnqueuing {}
