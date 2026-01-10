import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public private(set) var settings: UserSettings? = nil
    @Published public private(set) var skills: [SkillItem] = []
    @Published public private(set) var errorMessage: String? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isLoadingSkills: Bool = false
    @Published public private(set) var isSavingSkills: Bool = false
    @Published public private(set) var skillsError: String? = nil
    @Published public private(set) var shortcutsToken: String = ""
    @Published public private(set) var shortcutsError: String? = nil
    @Published public private(set) var isLoadingShortcuts: Bool = false
    @Published public private(set) var isRotatingShortcuts: Bool = false
    @Published public private(set) var profileImageData: Data? = nil
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
        let cached: UserSettings? = cache.get(key: CacheKeys.userSettings)
        if let cached {
            settings = cached
        }
        do {
            let response = try await settingsAPI.getSettings()
            settings = response
            cache.set(key: CacheKeys.userSettings, value: response, ttlSeconds: CachePolicy.userSettings)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    public func loadSkills() async {
        skillsError = nil
        isLoadingSkills = true
        let cached: SkillsResponse? = cache.get(key: CacheKeys.skillsList)
        if let cached {
            skills = cached.skills
        }
        do {
            let response = try await skillsAPI.list()
            skills = response.skills
            cache.set(key: CacheKeys.skillsList, value: response, ttlSeconds: CachePolicy.skillsList)
        } catch {
            if cached == nil {
                skillsError = error.localizedDescription
            }
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
        let cached: Data? = cache.get(key: CacheKeys.profileImage)
        if let cached {
            profileImageData = cached
        }
        isLoadingProfileImage = true
        do {
            let data = try await settingsAPI.getProfileImage()
            profileImageData = data
            cache.set(key: CacheKeys.profileImage, value: data, ttlSeconds: CachePolicy.profileImage)
        } catch {
            if cached == nil {
                profileImageData = nil
            }
        }
        isLoadingProfileImage = false
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
