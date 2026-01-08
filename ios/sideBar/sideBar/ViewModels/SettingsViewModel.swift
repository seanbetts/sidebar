import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public private(set) var settings: UserSettings? = nil
    @Published public private(set) var skills: [SkillItem] = []
    @Published public private(set) var errorMessage: String? = nil

    private let settingsAPI: SettingsAPI
    private let skillsAPI: SkillsAPI

    public init(settingsAPI: SettingsAPI, skillsAPI: SkillsAPI) {
        self.settingsAPI = settingsAPI
        self.skillsAPI = skillsAPI
    }

    public func load() async {
        errorMessage = nil
        do {
            settings = try await settingsAPI.getSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadSkills() async {
        errorMessage = nil
        do {
            skills = try await skillsAPI.list().skills
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
