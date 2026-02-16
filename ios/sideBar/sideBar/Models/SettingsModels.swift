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
public struct SettingsUpdate: Encodable {
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
    /// Includes `date_of_birth` even when nil so callers can clear it.
    public let includeDateOfBirth: Bool

    public init(
        communicationStyle: String? = nil,
        workingRelationship: String? = nil,
        name: String? = nil,
        jobTitle: String? = nil,
        employer: String? = nil,
        dateOfBirth: String? = nil,
        gender: String? = nil,
        pronouns: String? = nil,
        location: String? = nil,
        enabledSkills: [String]? = nil,
        includeDateOfBirth: Bool = false
    ) {
        self.communicationStyle = communicationStyle
        self.workingRelationship = workingRelationship
        self.name = name
        self.jobTitle = jobTitle
        self.employer = employer
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.pronouns = pronouns
        self.location = location
        self.enabledSkills = enabledSkills
        self.includeDateOfBirth = includeDateOfBirth
    }

    private enum CodingKeys: String, CodingKey {
        case communicationStyle = "communication_style"
        case workingRelationship = "working_relationship"
        case name
        case jobTitle = "job_title"
        case employer
        case dateOfBirth = "date_of_birth"
        case gender
        case pronouns
        case location
        case enabledSkills = "enabled_skills"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(communicationStyle, forKey: .communicationStyle)
        try container.encodeIfPresent(workingRelationship, forKey: .workingRelationship)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(jobTitle, forKey: .jobTitle)
        try container.encodeIfPresent(employer, forKey: .employer)
        if includeDateOfBirth {
            try container.encode(dateOfBirth, forKey: .dateOfBirth)
        } else {
            try container.encodeIfPresent(dateOfBirth, forKey: .dateOfBirth)
        }
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(pronouns, forKey: .pronouns)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(enabledSkills, forKey: .enabledSkills)
    }
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
