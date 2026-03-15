import Foundation

@MainActor
extension SettingsViewModel {
    static func dateOnlyString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    func invalidateAndRefreshSkillsState() async {
        cache.remove(key: userSettingsCacheKey)
        removeLegacyCacheKeyIfNeeded(
            currentKey: userSettingsCacheKey,
            legacyKey: CacheKeys.userSettings
        )
        cache.remove(key: CacheKeys.skillsList)
        await load(force: true)
        await loadSkills()
    }
}
