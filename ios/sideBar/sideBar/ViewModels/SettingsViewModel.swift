import Foundation
import Combine

// NOTE: Revisit to prefer native-first data sources where applicable.

@MainActor
/// Manages user settings, skills, and profile image state.
public final class SettingsViewModel: ObservableObject {
    @Published public private(set) var settings: UserSettings?
    @Published public private(set) var skills: [SkillItem] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isLoadingSkills: Bool = false
    @Published public private(set) var isSavingSkills: Bool = false
    @Published public private(set) var skillsError: String?
    @Published public private(set) var shortcutsToken: String = ""
    @Published public private(set) var shortcutsError: String?
    @Published public private(set) var isLoadingShortcuts: Bool = false
    @Published public private(set) var isRotatingShortcuts: Bool = false
    @Published public private(set) var profileImageData: Data?
    @Published public private(set) var isLoadingProfileImage: Bool = false

    private let settingsAPI: any SettingsProviding
    private let skillsAPI: any SkillsProviding
    private let cache: CacheClient

    public init(settingsAPI: any SettingsProviding, skillsAPI: any SkillsProviding, cache: CacheClient) {
        self.settingsAPI = settingsAPI
        self.skillsAPI = skillsAPI
        self.cache = cache
    }

    public func load() async {
        errorMessage = nil
        isLoading = true
        let loader = CachedLoader(
            cache: cache,
            key: CacheKeys.userSettings,
            ttl: CachePolicy.userSettings
        ) { [settingsAPI] in
            try await settingsAPI.getSettings()
        }
        do {
            let (response, _) = try await loader.load(onRefresh: { [weak self] fresh in
                self?.settings = fresh
            })
            settings = response
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public func loadSkills() async {
        skillsError = nil
        isLoadingSkills = true
        let loader = CachedLoader(
            cache: cache,
            key: CacheKeys.skillsList,
            ttl: CachePolicy.skillsList
        ) { [skillsAPI] in
            try await skillsAPI.list()
        }
        do {
            let (response, _) = try await loader.load(onRefresh: { [weak self] fresh in
                self?.skills = fresh.skills
            })
            skills = response.skills
        } catch {
            skillsError = error.localizedDescription
        }
        isLoadingSkills = false
    }

    public func loadShortcutsToken() async {
        shortcutsError = nil
        isLoadingShortcuts = true
        do {
            let response = try await settingsAPI.getShortcutsToken()
            shortcutsToken = response.token
        } catch {
            shortcutsError = error.localizedDescription
        }
        isLoadingShortcuts = false
    }

    public func rotateShortcutsToken() async {
        shortcutsError = nil
        isRotatingShortcuts = true
        do {
            let response = try await settingsAPI.rotateShortcutsToken()
            shortcutsToken = response.token
        } catch {
            shortcutsError = error.localizedDescription
        }
        isRotatingShortcuts = false
    }

    public func loadProfileImage() async {
        guard let settings, settings.profileImageUrl != nil else {
            profileImageData = nil
            cache.remove(key: CacheKeys.profileImage)
            return
        }
        isLoadingProfileImage = true
        let loader = CachedLoader(
            cache: cache,
            key: CacheKeys.profileImage,
            ttl: CachePolicy.profileImage
        ) { [settingsAPI] in
            try await settingsAPI.getProfileImage()
        }
        do {
            let (data, _) = try await loader.load(onRefresh: { [weak self] fresh in
                self?.profileImageData = fresh
            })
            profileImageData = data
        } catch {
            profileImageData = nil
        }
        isLoadingProfileImage = false
    }

    public func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        try await settingsAPI.uploadProfileImage(data: data, contentType: contentType, filename: filename)
        profileImageData = data
        cache.set(key: CacheKeys.profileImage, value: data, ttlSeconds: CachePolicy.profileImage)
        if settings?.profileImageUrl == nil {
            await load()
        }
    }

    public func setSkillEnabled(id: String, enabled: Bool) async {
        guard let settings else { return }
        var next = settings.enabledSkills
        if enabled {
            if !next.contains(id) {
                next.append(id)
            }
        } else {
            next.removeAll { $0 == id }
        }
        await updateEnabledSkills(next)
    }

    public func setAllSkillsEnabled(_ enabled: Bool) async {
        let next = enabled ? skills.map(\.id) : []
        await updateEnabledSkills(next)
    }

    private func updateEnabledSkills(_ enabledSkills: [String]) async {
        skillsError = nil
        isSavingSkills = true
        let previous = settings
        if let current = settings {
            settings = UserSettings(
                userId: current.userId,
                communicationStyle: current.communicationStyle,
                workingRelationship: current.workingRelationship,
                name: current.name,
                jobTitle: current.jobTitle,
                employer: current.employer,
                dateOfBirth: current.dateOfBirth,
                gender: current.gender,
                pronouns: current.pronouns,
                location: current.location,
                profileImageUrl: current.profileImageUrl,
                enabledSkills: enabledSkills
            )
        }
        do {
            let update = SettingsUpdate(
                communicationStyle: nil,
                workingRelationship: nil,
                name: nil,
                jobTitle: nil,
                employer: nil,
                dateOfBirth: nil,
                gender: nil,
                pronouns: nil,
                location: nil,
                enabledSkills: enabledSkills
            )
            let response = try await settingsAPI.updateSettings(update)
            settings = response
            cache.set(key: CacheKeys.userSettings, value: response, ttlSeconds: CachePolicy.userSettings)
        } catch {
            settings = previous
            skillsError = error.localizedDescription
        }
        isSavingSkills = false
    }
}
