import Foundation
import sideBarShared

extension SettingsStore {
    func apply(_ settings: UserSettings, persist: Bool) {
        self.settings = settings
        guard persist else {
            return
        }

        cache.set(key: cacheKey, value: settings, ttlSeconds: CachePolicy.userSettings)
        offlineStore?.set(
            key: cacheKey,
            entityType: "settings",
            value: settings,
            lastSyncAt: offlineStore?.lastSyncAt(for: cacheKey)
        )
    }
}
