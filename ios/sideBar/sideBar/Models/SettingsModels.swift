import Foundation
import Combine

public struct UserSettings: Codable {
    public let userId: String
    public let communicationStyle: String?
    public let workingRelationship: String?
    public let name: String?
    public let jobTitle: String?
    public let employer: String?
    public let dateOfBirth: String?
    public let gender: String?
    public let pronouns: String?
    public let location: String?
    public let profileImageUrl: String?
    public let enabledSkills: [String]
}

public struct SettingsUpdate: Codable {
    public let communicationStyle: String?
    public let workingRelationship: String?
    public let name: String?
    public let jobTitle: String?
    public let employer: String?
    public let dateOfBirth: String?
    public let gender: String?
    public let pronouns: String?
    public let location: String?
    public let enabledSkills: [String]?
}

public struct SkillItem: Codable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let category: String
}

public struct SkillsResponse: Codable {
    public let skills: [SkillItem]
}

public struct ShortcutsTokenResponse: Codable {
    public let token: String
}
