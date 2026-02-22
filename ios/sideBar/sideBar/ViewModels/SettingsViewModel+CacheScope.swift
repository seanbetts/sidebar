import Foundation

extension SettingsViewModel {
    public func isSkillUserToggleable(id: String) -> Bool {
        skills.first { $0.id == id }?.userToggleable ?? true
    }

    var userSettingsCacheKey: String {
        cacheKey(for: CacheKeys.userSettings)
    }

    var profileImageCacheKey: String {
        cacheKey(for: CacheKeys.profileImage)
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

    func removeLegacyCacheKeyIfNeeded(currentKey: String, legacyKey: String) {
        guard currentKey != legacyKey else { return }
        cache.remove(key: legacyKey)
    }
}
