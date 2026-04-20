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
    let currentAuthUserIdProvider: () -> String?
    let pendingSecretStore: (any SettingsPendingSecretStoring)?
    let pendingAssetStore: (any SettingsPendingAssetStoring)?
    weak var writeQueue: (any SettingsWriteQueueEnqueuing)?

    init(
        settingsAPI: any SettingsProviding,
        cache: CacheClient,
        offlineStore: OfflineStore? = nil,
        pendingSecretStore: (any SettingsPendingSecretStoring)? = nil,
        pendingAssetStore: (any SettingsPendingAssetStoring)? = nil,
        currentAuthUserIdProvider: @escaping () -> String? = { nil },
        writeQueue: (any SettingsWriteQueueEnqueuing)? = nil
    ) {
        self.settingsAPI = settingsAPI
        self.cache = cache
        self.offlineStore = offlineStore
        self.pendingSecretStore = pendingSecretStore
        self.pendingAssetStore = pendingAssetStore
        self.currentAuthUserIdProvider = currentAuthUserIdProvider
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

    func reset() {
        settings = nil
    }

    func attachWriteQueue<Queue: SettingsWriteQueueEnqueuing>(_ writeQueue: Queue) {
        self.writeQueue = writeQueue
    }

    func replace(_ settings: UserSettings, persist: Bool) {
        apply(settings, persist: persist)
    }

    func currentSnapshotForMutation() -> UserSettings? {
        if let settings {
            return settings
        }
        if let cached: UserSettings = cache.get(key: cacheKey) {
            return cached
        }
        return offlineStore?.get(key: cacheKey, as: UserSettings.self)
    }

    var cacheKey: String {
        cacheKey(for: CacheKeys.userSettings)
    }

    func cacheKey(for baseKey: String) -> String {
        guard
            let userId = currentAuthUserIdProvider()?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !userId.isEmpty
        else {
            return baseKey
        }
        return "\(baseKey).\(userId)"
    }
}

enum SettingsStoreError: Error {
    case missingCurrentSnapshot
    case missingWriteQueue
    case missingPendingSecretStore
    case missingPendingAssetStore
}
