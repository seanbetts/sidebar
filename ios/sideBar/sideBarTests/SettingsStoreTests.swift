import Foundation
import sideBarShared
import XCTest
@testable import sideBar

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testLoadPrefersOfflineSnapshotWhenServerReadFails() async throws {
        let cachedSettings = makeSettings(name: "Offline snapshot")
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.userSettings, value: cachedSettings, ttlSeconds: 60)
        let api = SettingsStoreAPISpy(
            getSettingsResult: .failure(SettingsStoreTestError.forced)
        )
        let writeQueue = SettingsWriteQueueSpy()
        let store = SettingsStore(
            settingsAPI: api,
            cache: cache,
            writeQueue: writeQueue
        )

        let loaded = try await store.load()

        XCTAssertEqual(loaded, cachedSettings)
        XCTAssertEqual(store.settings, cachedSettings)
        XCTAssertEqual(api.getSettingsCallCount, 1)
        XCTAssertEqual(writeQueue.enqueuedWrites.count, 0)
    }

    func testCommitUserPatchUpdatesLocalSnapshotAndEnqueuesSettingsWrite() async throws {
        let initialSettings = makeSettings(name: "Initial")
        let cache = TestCacheClient()
        cache.set(key: CacheKeys.userSettings, value: initialSettings, ttlSeconds: 60)
        let api = SettingsStoreAPISpy(
            getSettingsResult: .success(initialSettings),
            updateSettingsResult: .success(initialSettings)
        )
        let writeQueue = SettingsWriteQueueSpy()
        let store = SettingsStore(
            settingsAPI: api,
            cache: cache,
            writeQueue: writeQueue
        )
        let patch = SettingsMutationPayload(name: "Ada Lovelace")

        try await store.commitUserPatch(patch)

        XCTAssertEqual(store.settings?.name, "Ada Lovelace")
        XCTAssertEqual(writeQueue.enqueuedWrites, [queuedSettingsWrite(patch)])
        XCTAssertEqual(api.updateSettingsCallCount, 0)
    }
}

private func queuedSettingsWrite(_ payload: SettingsMutationPayload) -> PendingWriteRecord {
    let payloadData = try! JSONEncoder().encode(payload)
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
