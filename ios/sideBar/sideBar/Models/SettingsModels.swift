import Foundation
import Combine

/// Represents an user settings struct.
public struct UserSettings: Codable {
    /// The user id value.
    public let userId: String
    /// The communication style value.
    public let communicationStyle: String?
    /// The working relationship value.
    public let workingRelationship: String?
    /// The name value.
    public let name: String?
    /// The job title value.
    public let jobTitle: String?
    /// The employer value.
    public let employer: String?
    /// The date of birth value.
    public let dateOfBirth: String?
    /// The gender value.
    public let gender: String?
    /// The pronouns value.
    public let pronouns: String?
    /// The location value.
    public let location: String?
    /// The profile image url value.
    public let profileImageUrl: String?
    /// The enabled skills value.
    public let enabledSkills: [String]
}

/// Represents a settings update struct.
public struct SettingsUpdate: Codable {
    /// The communication style value.
    public let communicationStyle: String?
    /// The working relationship value.
    public let workingRelationship: String?
    /// The name value.
    public let name: String?
    /// The job title value.
    public let jobTitle: String?
    /// The employer value.
    public let employer: String?
    /// The date of birth value.
    public let dateOfBirth: String?
    /// The gender value.
    public let gender: String?
    /// The pronouns value.
    public let pronouns: String?
    /// The location value.
    public let location: String?
    /// The enabled skills value.
    public let enabledSkills: [String]?
}

/// Represents a skill item struct.
public struct SkillItem: Codable, Identifiable {
    /// The id value.
    public let id: String
    /// The name value.
    public let name: String
    /// The description value.
    public let description: String
    /// The category value.
    public let category: String
}

/// Represents a skills response struct.
public struct SkillsResponse: Codable {
    /// The skills value.
    public let skills: [SkillItem]
}

/// Represents a shortcuts token response struct.
public struct ShortcutsTokenResponse: Codable {
    /// The token value.
    public let token: String
}
