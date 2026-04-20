import Foundation
import Combine
import sideBarShared

// NOTE: Revisit to prefer native-first data sources where applicable.

@MainActor
/// Manages user settings, skills, and profile image state.
public final class SettingsViewModel: LoadableViewModel {
    static let defaultAssistantDisplayName = "sideBar"

    @Published public private(set) var settings: UserSettings?
    @Published public private(set) var skills: [SkillItem] = []
    @Published public private(set) var isLoadingSkills: Bool = false
    @Published public private(set) var isSavingSkills: Bool = false
    @Published public private(set) var skillsError: String?
    @Published public private(set) var shortcutsToken: String = ""
    @Published public private(set) var shortcutsError: String?
    @Published public private(set) var isLoadingShortcuts: Bool = false
    @Published public private(set) var isRotatingShortcuts: Bool = false
    @Published public internal(set) var profileImageData: Data?
    @Published public internal(set) var isLoadingProfileImage: Bool = false
    @Published public private(set) var isSavingProfile: Bool = false
    @Published public private(set) var profileSaveError: String?
    @Published public internal(set) var isSavingSystem: Bool = false
    @Published public internal(set) var systemSaveError: String?
    @Published public internal(set) var settingsSaveCompletionCount: Int = 0
    @Published public private(set) var isSavingPrimaryProvider: Bool = false
    @Published public private(set) var primaryProviderError: String?
    @Published public private(set) var onboardingState: OnboardingState?
    @Published public private(set) var isLoadingOnboarding: Bool = false
    @Published public internal(set) var isInternalDiagnosticsLocallyUnlocked: Bool
    var isRefreshingProviderRecoveryState = false
    var inFlightProfileImageLoad: Task<Data?, Never>?
    var internalDiagnosticsRevealTapCount: Int = 0
    var lastInternalDiagnosticsUserId: String?

    let settingsAPI: any SettingsProviding
    let skillsAPI: any SkillsProviding
    let onboardingAPI: (any OnboardingProviding)?
    let locationPermissionRequester: any LocationPermissionRequesting
    let notificationPermissionRequester: any NotificationPermissionRequesting
    let cache: CacheClient
    let settingsStore: SettingsStore
    let currentAuthUserIdProvider: () -> String?
    let currentAuthorizedUserIdProvider: (() -> String?)?
    let refreshAuthorizedSession: (() async -> Void)?
    let userDefaults: UserDefaults

    public init(
        settingsAPI: any SettingsProviding,
        skillsAPI: any SkillsProviding,
        onboardingAPI: (any OnboardingProviding)? = nil,
        locationPermissionRequester: (any LocationPermissionRequesting)? = nil,
        notificationPermissionRequester: (any NotificationPermissionRequesting)? = nil,
        cache: CacheClient,
        settingsStore: SettingsStore? = nil,
        currentAuthUserIdProvider: @escaping () -> String? = { nil },
        currentAuthorizedUserIdProvider: (() -> String?)? = nil,
        refreshAuthorizedSession: (() async -> Void)? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.settingsAPI = settingsAPI
        self.skillsAPI = skillsAPI
        self.onboardingAPI = onboardingAPI
        self.locationPermissionRequester = locationPermissionRequester ?? LocationPermissionRequester()
        self.notificationPermissionRequester = notificationPermissionRequester ?? NotificationPermissionRequester()
        self.cache = cache
        self.settingsStore = settingsStore ?? SettingsStore(
            settingsAPI: settingsAPI,
            cache: cache
        )
        self.currentAuthUserIdProvider = currentAuthUserIdProvider
        self.currentAuthorizedUserIdProvider = currentAuthorizedUserIdProvider
        self.refreshAuthorizedSession = refreshAuthorizedSession
        self.userDefaults = userDefaults
        self.isInternalDiagnosticsLocallyUnlocked = userDefaults.bool(
            forKey: AppStorageKeys.internalDiagnosticsUnlocked
        )
        super.init()
    }

    public func load(force: Bool = false) async {
        clearError()
        profileSaveError = nil
        systemSaveError = nil
        primaryProviderError = nil
        setLoading(true)
        do {
            let response = try await settingsStore.load(force: force)
            synchronizeInternalDiagnosticsSessionScope(with: response)
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
            skillsError = settingsErrorMessage(
                for: error,
                operation: "settings.skills.list",
                requestKind: .foregroundRead
            )
        }
        isLoadingSkills = false
    }

    public func loadOnboarding(force: Bool = false) async {
        _ = force
        guard let onboardingAPI else {
            onboardingState = nil
            return
        }

        isLoadingOnboarding = true
        defer { isLoadingOnboarding = false }

        do {
            let state = try await onboardingAPI.getOnboarding()
            setOnboardingState(state)
        } catch {}
    }

    func setOnboardingState(_ state: OnboardingState?) {
        onboardingState = normalizedOnboardingStateForPresentation(state)
    }

    public func loadShortcutsToken() async {
        shortcutsError = nil
        isLoadingShortcuts = true
        do {
            let response = try await settingsAPI.getShortcutsToken()
            shortcutsToken = response.token
        } catch {
            shortcutsError = settingsErrorMessage(
                for: error,
                operation: "settings.shortcutsToken.read",
                requestKind: .foregroundRead
            )
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
            shortcutsError = settingsErrorMessage(
                for: error,
                operation: "settings.shortcutsToken.rotate",
                requestKind: .foregroundMutation
            )
        }
        isRotatingShortcuts = false
    }

    public func uploadProfileImage(data: Data, contentType: String, filename: String) async throws {
        try await settingsAPI.uploadProfileImage(data: data, contentType: contentType, filename: filename)
        profileImageData = data
        cache.set(key: profileImageCacheKey, value: data, ttlSeconds: CachePolicy.profileImage)
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
        profileSaveError = nil
        let resolved = await currentSettingsForSave()
        guard let current = resolved.settings else { profileSaveError = resolved.error; return }

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
        logSettingsSaveAttempt(operation: "profile", changedFields: [
            nameUpdate == nil ? nil : "name",
            jobTitleUpdate == nil ? nil : "job_title",
            employerUpdate == nil ? nil : "employer",
            didChangeDateOfBirth ? "date_of_birth" : nil,
            genderUpdate == nil ? nil : "gender",
            pronounsUpdate == nil ? nil : "pronouns",
            locationUpdate == nil ? nil : "location"
        ].compactMap { $0 })
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
            applySettingsResponse(response)
            settingsSaveCompletionCount += 1
        } catch {
            profileSaveError = recordSettingsSaveFailure(
                error,
                operation: "profile"
            )
        }
        isSavingProfile = false
    }

    public func saveUserSettings(
        communicationStyle: String,
        workingRelationship: String
    ) async {
        systemSaveError = nil
        let resolved = await currentSettingsForSave()
        guard let current = resolved.settings else { systemSaveError = resolved.error; return }

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
        logSettingsSaveAttempt(operation: "user", changedFields: [
            communicationStyleUpdate == nil ? nil : "communication_style",
            workingRelationshipUpdate == nil ? nil : "working_relationship"
        ].compactMap { $0 })
        do {
            let response = try await settingsAPI.updateSettings(
                SettingsUpdate(
                    communicationStyle: communicationStyleUpdate,
                    workingRelationship: workingRelationshipUpdate
                )
            )
            applySettingsResponse(response)
            settingsSaveCompletionCount += 1
        } catch {
            systemSaveError = recordSettingsSaveFailure(
                error,
                operation: "user"
            )
        }
        isSavingSystem = false
    }

    public func setSkillEnabled(id: String, enabled: Bool) async {
        guard let settings else { return }
        guard isSkillUserToggleable(id: id) else { return }
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
        let currentEnabled = settings?.enabledSkills ?? []
        let toggleableSkillIds = Set(skills.filter(\.userToggleable).map(\.id))
        let requiredSkillIds = Set(skills.filter { !$0.userToggleable }.map(\.id))
        var next = Set(currentEnabled)
        if enabled {
            next.formUnion(toggleableSkillIds)
        } else {
            next.subtract(toggleableSkillIds)
        }
        next.formUnion(requiredSkillIds)
        let ordered = skills.map(\.id).filter { next.contains($0) }
        await updateEnabledSkills(ordered)
    }

    private func updateEnabledSkills(_ enabledSkills: [String]) async {
        skillsError = nil
        isSavingSkills = true
        let previous = settings
        let normalized = normalizeEnabledSkills(enabledSkills)
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
                notificationPreferences: current.notificationPreferences,
                assistantIdentity: current.assistantIdentity,
                assistantIdentityMeta: current.assistantIdentityMeta,
                assistantSoul: current.assistantSoul,
                assistantSoulMeta: current.assistantSoulMeta,
                aiPrimaryProvider: current.aiPrimaryProvider,
                aiPrimaryProviderHasKey: current.aiPrimaryProviderHasKey,
                aiPrimaryProviderKeyLast4: current.aiPrimaryProviderKeyLast4,
                enabledSkills: normalized,
                installedStoreSkills: current.installedStoreSkills
            )
        }
        do {
            let update = SettingsUpdate(
                enabledSkills: normalized
            )
            logSettingsSaveAttempt(
                operation: "skills",
                changedFields: ["enabled_skills"]
            )
            let response = try await settingsAPI.updateSettings(update)
            applySettingsResponse(response)
            settingsSaveCompletionCount += 1
            await invalidateAndRefreshSkillsState()
        } catch {
            settings = previous
            skillsError = recordSettingsSaveFailure(
                error,
                operation: "skills"
            )
        }
        isSavingSkills = false
    }

    func setPrimaryProviderSaving(_ isSaving: Bool) { isSavingPrimaryProvider = isSaving }

    func setPrimaryProviderError(_ error: String?) { primaryProviderError = error }

    func recordCompletedSettingsSave() { settingsSaveCompletionCount += 1 }

    func reset() {
        setLoading(false)
        clearError()

        settings = nil
        settingsStore.reset()
        skills = []
        isLoadingSkills = false
        isSavingSkills = false
        skillsError = nil

        shortcutsToken = ""
        shortcutsError = nil
        isLoadingShortcuts = false
        isRotatingShortcuts = false

        profileImageData = nil
        isLoadingProfileImage = false
        isSavingProfile = false
        profileSaveError = nil

        isSavingSystem = false
        systemSaveError = nil
        settingsSaveCompletionCount = 0

        isSavingPrimaryProvider = false
        primaryProviderError = nil
        onboardingState = nil
        isLoadingOnboarding = false
        internalDiagnosticsRevealTapCount = 0
    }

    func applySettingsResponse(_ response: UserSettings) {
        settingsStore.replace(response, persist: true)
        synchronizeInternalDiagnosticsSessionScope(with: response)
        settings = response
    }
}

@MainActor
extension SettingsViewModel {
    public func setAllSkillsEnabled(_ enabled: Bool, scopeSkillIds: Set<String>) async {
        let currentEnabled = settings?.enabledSkills ?? []
        let toggleableSkillIds = Set(
            skills
                .filter(\.userToggleable)
                .map(\.id)
                .filter { scopeSkillIds.contains($0) }
        )
        let requiredSkillIds = Set(skills.filter { !$0.userToggleable }.map(\.id))
        var next = Set(currentEnabled)
        if enabled {
            next.formUnion(toggleableSkillIds)
        } else {
            next.subtract(toggleableSkillIds)
        }
        next.formUnion(requiredSkillIds)
        let ordered = skills.map(\.id).filter { next.contains($0) }
        await updateEnabledSkills(ordered)
    }

    public func installStoreSkill(
        id: String,
        providerKeys: [StoreSkillProviderKeyInput] = []
    ) async -> Bool {
        skillsError = nil
        isSavingSkills = true
        defer { isSavingSkills = false }

        do {
            _ = try await skillsAPI.installStoreSkill(skillId: id, providerKeys: providerKeys)
            await invalidateAndRefreshSkillsState()
            return true
        } catch {
            skillsError = settingsErrorMessage(
                for: error,
                operation: "settings.skills.install",
                requestKind: .foregroundMutation
            )
            return false
        }
    }

    public func uninstallStoreSkill(id: String) async -> Bool {
        skillsError = nil
        isSavingSkills = true
        defer { isSavingSkills = false }

        do {
            _ = try await skillsAPI.uninstallStoreSkill(skillId: id)
            await invalidateAndRefreshSkillsState()
            return true
        } catch {
            skillsError = settingsErrorMessage(
                for: error,
                operation: "settings.skills.uninstall",
                requestKind: .foregroundMutation
            )
            return false
        }
    }
    func settingsErrorMessage(
        for error: Error,
        operation: String,
        requestKind: RequestKind?
    ) -> String {
        ErrorMapping.presentation(
            for: error,
            operation: operation,
            requestKind: requestKind
        ).message
    }
}
