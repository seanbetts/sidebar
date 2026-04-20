import Combine
import Foundation
import sideBarShared

@MainActor
/// Canonical owner of the active user settings snapshot and local persistence wiring.
public final class SettingsStore: ObservableObject {
    @Published public internal(set) var settings: UserSettings?

    let settingsAPI: any SettingsProviding
    let cache: CacheClient
    let offlineStore: OfflineStore?
    weak var writeQueue: (any SettingsWriteQueueEnqueuing)?

    init(
        settingsAPI: any SettingsProviding,
        cache: CacheClient,
        offlineStore: OfflineStore? = nil,
        writeQueue: (any SettingsWriteQueueEnqueuing)? = nil
    ) {
        self.settingsAPI = settingsAPI
        self.cache = cache
        self.offlineStore = offlineStore
        self.writeQueue = writeQueue
    }

    public func load(force: Bool = false) async throws -> UserSettings {
        let cached: UserSettings? = force ? nil : cache.get(key: cacheKey)
        if let cached {
            settings = cached
        }

        do {
            let remote = try await settingsAPI.getSettings()
            apply(remote, persist: true)
            return remote
        } catch {
            if let offline = offlineStore?.get(key: cacheKey, as: UserSettings.self) {
                apply(offline, persist: false)
                return offline
            }
            if let cached {
                apply(cached, persist: false)
                return cached
            }
            throw error
        }
    }

    public func commitUserPatch(_ patch: SettingsMutationPayload) async throws {
        guard let current = currentSnapshotForMutation() else {
            throw SettingsStoreError.missingCurrentSnapshot
        }

        let next = current.applying(patch: patch)
        apply(next, persist: true)

        let write = PendingWriteRecord(
            id: UUID(),
            operationType: WriteOperation.update.rawValue,
            entityType: WriteEntityType.settings.rawValue,
            entityId: patch.entityId,
            payload: try JSONEncoder().encode(patch),
            serverSnapshot: nil,
            attempts: 0
        )
        try await writeQueue?.enqueue(write)
    }

    func reset() {
        settings = nil
    }

    func replace(_ settings: UserSettings, persist: Bool) {
        apply(settings, persist: persist)
    }

    private func currentSnapshotForMutation() -> UserSettings? {
        if let settings {
            return settings
        }
        if let cached: UserSettings = cache.get(key: cacheKey) {
            return cached
        }
        return offlineStore?.get(key: cacheKey, as: UserSettings.self)
    }

    var cacheKey: String {
        CacheKeys.userSettings
    }
}

enum SettingsStoreError: Error {
    case missingCurrentSnapshot
}

@MainActor
protocol SettingsWriteQueueEnqueuing: AnyObject {
    func enqueue(_ write: PendingWriteRecord) async throws
}
