import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testLoadPrefersOfflineSnapshotWhenServerReadFails() async throws {
        let cachedSettings = makeSettings(name: "Stale cache snapshot")
        let offlineSnapshot = makeSettings(name: "Offline snapshot")
        let cache = SettingsPersistenceSpy()
        cache.stage(key: CacheKeys.userSettings, value: cachedSettings)
        let offlineStore = SettingsOfflineSnapshotStoreSpy()
        offlineStore.stage(snapshot: offlineSnapshot, for: CacheKeys.userSettings)
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

        XCTAssertEqual(loaded, offlineSnapshot)
        XCTAssertEqual(store.settings, offlineSnapshot)
        XCTAssertEqual(offlineStore.lookupCallCount, 1)
        XCTAssertEqual(offlineStore.lastLookupKey, CacheKeys.userSettings)
        XCTAssertEqual(api.getSettingsCallCount, 1)
        XCTAssertEqual(writeQueue.enqueuedWrites.count, 0)
    }

    func testCommitUserPatchUpdatesLocalSnapshotAndEnqueuesSettingsWrite() async throws {
        let initialSettings = makeSettings(name: "Initial")
        let cache = SettingsPersistenceSpy()
        cache.stage(key: CacheKeys.userSettings, value: initialSettings)
        let offlineStore = SettingsOfflineSnapshotStoreSpy()
        offlineStore.stage(snapshot: initialSettings, for: CacheKeys.userSettings)
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
        let patch = SettingsMutationPayload(name: "Ada Lovelace")

        try await store.commitUserPatch(patch)

        XCTAssertEqual(store.settings?.name, "Ada Lovelace")
        XCTAssertEqual(cache.setCallCount, 1)
        XCTAssertEqual(offlineStore.setCallCount, 1)
        XCTAssertEqual(try cache.snapshot(for: CacheKeys.userSettings)?.name, "Ada Lovelace")
        XCTAssertEqual(try offlineStore.snapshot(for: CacheKeys.userSettings)?.name, "Ada Lovelace")
        XCTAssertEqual(writeQueue.enqueuedWrites.count, 1)
        let enqueuedWrite = try XCTUnwrap(writeQueue.enqueuedWrites.first)
        XCTAssertEqual(enqueuedWrite.operationType, WriteOperation.update.rawValue)
        XCTAssertEqual(enqueuedWrite.entityType, WriteEntityType.settings.rawValue)
        XCTAssertEqual(enqueuedWrite.entityId, patch.entityId)
        let decodedPayload = try JSONDecoder().decode(SettingsMutationPayload.self, from: enqueuedWrite.payload)
        XCTAssertEqual(decodedPayload.name, patch.name)
        XCTAssertEqual(api.updateSettingsCallCount, 0)
    }
}

private func makeSettings(name: String?) -> UserSettings {
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
        profileImageUrl: nil,
        enabledSkills: []
    )
}

private enum SettingsStoreTestError: Error {
    case forced
}

@MainActor
private final class SettingsOfflineSnapshotStoreSpy {
    private var snapshots: [String: Data] = [:]
    private(set) var lookupCallCount = 0
    private(set) var setCallCount = 0
    private(set) var lastLookupKey: String?
    private(set) var lastSetKey: String?

    func stage(snapshot: UserSettings, for key: String) {
        snapshots[key] = try? JSONEncoder().encode(snapshot)
    }

    func get<T: Decodable>(key: String, as type: T.Type) -> T? {
        lookupCallCount += 1
        lastLookupKey = key
        guard let snapshot = snapshots[key] else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: snapshot)
    }

    func set<T: Encodable>(key: String, entityType: String, value: T, lastSyncAt: Date?) {
        _ = entityType
        _ = lastSyncAt
        setCallCount += 1
        lastSetKey = key
        snapshots[key] = try? JSONEncoder().encode(value)
    }

    func snapshot<T: Decodable>(for key: String, as type: T.Type = T.self) throws -> T? {
        guard let snapshot = snapshots[key] else {
            return nil
        }
        return try JSONDecoder().decode(T.self, from: snapshot)
    }
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

    func enqueue(_ write: PendingWriteRecord) async {
        enqueuedWrites.append(write)
    }
}
