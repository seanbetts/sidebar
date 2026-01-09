import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public private(set) var settings: UserSettings? = nil
    @Published public private(set) var skills: [SkillItem] = []
    @Published public private(set) var errorMessage: String? = nil

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
    }

    public func loadSkills() async {
        errorMessage = nil
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
                errorMessage = error.localizedDescription
            }
        }
    }
}
