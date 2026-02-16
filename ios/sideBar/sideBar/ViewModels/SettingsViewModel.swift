import Foundation
import Combine

// NOTE: Revisit to prefer native-first data sources where applicable.

@MainActor
/// Manages user settings, skills, and profile image state.
public final class SettingsViewModel: LoadableViewModel {
    @Published public private(set) var settings: UserSettings?
    @Published public private(set) var skills: [SkillItem] = []
    @Published public private(set) var isLoadingSkills: Bool = false
    @Published public private(set) var isSavingSkills: Bool = false
    @Published public private(set) var skillsError: String?
    @Published public private(set) var shortcutsToken: String = ""
    @Published public private(set) var shortcutsError: String?
    @Published public private(set) var isLoadingShortcuts: Bool = false
    @Published public private(set) var isRotatingShortcuts: Bool = false
    @Published public private(set) var profileImageData: Data?
    @Published public private(set) var isLoadingProfileImage: Bool = false
    @Published public private(set) var isSavingProfile: Bool = false
    @Published public private(set) var profileSaveError: String?
    @Published public private(set) var isSavingSystem: Bool = false
    @Published public private(set) var systemSaveError: String?

    private let settingsAPI: any SettingsProviding
    private let skillsAPI: any SkillsProviding
    private let cache: CacheClient

    public init(settingsAPI: any SettingsProviding, skillsAPI: any SkillsProviding, cache: CacheClient) {
        self.settingsAPI = settingsAPI
        self.skillsAPI = skillsAPI
        self.cache = cache
        super.init()
    }

    public func load() async {
        clearError()
        profileSaveError = nil
        systemSaveError = nil
        setLoading(true)
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
            setError(error)
        }
        setLoading(false)
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

    public func saveProfileSettings(
        name: String,
        jobTitle: String,
        employer: String,
        dateOfBirth: Date?,
        dateOfBirthEnabled: Bool,
        gender: String,
        pronouns: String,
        location: String
    ) async {
        guard let current = settings else { return }

        let nextDateOfBirth = dateOfBirthEnabled ? dateOfBirth.map(Self.dateOnlyString(from:)) : nil
        let nameUpdate = name != (current.name ?? "") ? name : nil
        let jobTitleUpdate = jobTitle != (current.jobTitle ?? "") ? jobTitle : nil
        let employerUpdate = employer != (current.employer ?? "") ? employer : nil
        let genderUpdate = gender != (current.gender ?? "") ? gender : nil
        let pronounsUpdate = pronouns != (current.pronouns ?? "") ? pronouns : nil
        let locationUpdate = location != (current.location ?? "") ? location : nil
        let didChangeDateOfBirth = nextDateOfBirth != current.dateOfBirth

        if nameUpdate == nil,
           jobTitleUpdate == nil,
           employerUpdate == nil,
           genderUpdate == nil,
           pronounsUpdate == nil,
           locationUpdate == nil,
           !didChangeDateOfBirth {
            return
        }

        isSavingProfile = true
        profileSaveError = nil
        do {
            let response = try await settingsAPI.updateSettings(
                SettingsUpdate(
                    name: nameUpdate,
                    jobTitle: jobTitleUpdate,
                    employer: employerUpdate,
                    dateOfBirth: didChangeDateOfBirth ? nextDateOfBirth : nil,
                    gender: genderUpdate,
                    pronouns: pronounsUpdate,
                    location: locationUpdate,
                    includeDateOfBirth: didChangeDateOfBirth
                )
            )
            settings = response
            cache.set(
                key: CacheKeys.userSettings,
                value: response,
                ttlSeconds: CachePolicy.userSettings
            )
        } catch {
            profileSaveError = error.localizedDescription
        }
        isSavingProfile = false
    }

    public func saveSystemSettings(
        communicationStyle: String,
        workingRelationship: String
    ) async {
        guard let current = settings else { return }

        let communicationStyleUpdate = communicationStyle != (current.communicationStyle ?? "")
            ? communicationStyle
            : nil
        let workingRelationshipUpdate = workingRelationship != (current.workingRelationship ?? "")
            ? workingRelationship
            : nil

        if communicationStyleUpdate == nil, workingRelationshipUpdate == nil {
            return
        }

        isSavingSystem = true
        systemSaveError = nil
        do {
            let response = try await settingsAPI.updateSettings(
                SettingsUpdate(
                    communicationStyle: communicationStyleUpdate,
                    workingRelationship: workingRelationshipUpdate
                )
            )
            settings = response
            cache.set(
                key: CacheKeys.userSettings,
                value: response,
                ttlSeconds: CachePolicy.userSettings
            )
        } catch {
            systemSaveError = error.localizedDescription
        }
        isSavingSystem = false
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

    private static func dateOnlyString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
