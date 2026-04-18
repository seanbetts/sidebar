import Foundation
import sideBarShared

@MainActor
extension SettingsViewModel {
    public func loadProfileImage() async {
        guard let settings,
              settings.profileImageUrl?.trimmedOrNil != nil else {
            profileImageData = nil
            cache.remove(key: profileImageCacheKey)
            removeLegacyCacheKeyIfNeeded(
                currentKey: profileImageCacheKey,
                legacyKey: CacheKeys.profileImage
            )
            return
        }

        if let inFlightProfileImageLoad {
            profileImageData = await inFlightProfileImageLoad.value
            return
        }

        isLoadingProfileImage = true
        StartupDebugTrace.log(
            "settings.profile-image.load.start",
            details: ["has_cached_data": profileImageData == nil ? "false" : "true"]
        )
        let task = Task { @MainActor [weak self] () -> Data? in
            guard let self else { return nil }

            let loader = CachedLoader(
                cache: cache,
                key: profileImageCacheKey,
                ttl: CachePolicy.profileImage
            ) { [settingsAPI] in
                try await settingsAPI.getProfileImage()
            }

            do {
                let (data, _) = try await loader.load(onRefresh: { [weak self] fresh in
                    self?.profileImageData = fresh
                })
                return data
            } catch {
                return nil
            }
        }

        inFlightProfileImageLoad = task
        let data = await task.value
        inFlightProfileImageLoad = nil
        profileImageData = data
        isLoadingProfileImage = false
        StartupDebugTrace.log(
            "settings.profile-image.load.end",
            details: ["has_data": data == nil ? "false" : "true"]
        )
    }
}
