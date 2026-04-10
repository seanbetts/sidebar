import Foundation
import Combine

/// Represents assistant identity guidance settings.
public struct AssistantIdentitySettings: Codable, Equatable {
    /// The assistant's preferred self-name.
    public let name: String?
    /// The assistant's default interaction tone.
    public let tone: String?
    /// The assistant's core values.
    public let values: String?
    /// The assistant's hard boundaries.
    public let boundaries: String?
}

/// Represents assistant soul guidance settings.
public struct AssistantSoulSettings: Codable, Equatable {
    /// The assistant's long-term purpose for this user.
    public let purpose: String?
    /// The assistant's operating principles.
    public let operatingPrinciples: String?
    /// The assistant's adaptation policy.
    public let adaptationPolicy: String?
    /// Signals that indicate assistant performance is improving.
    public let successSignals: String?
}

/// Metadata for assistant-managed settings fields.
public struct AgentFieldMeta: Codable, Equatable {
    /// Last update time in ISO-8601 format.
    public let updatedAt: String
    /// Monotonic version number for the field.
    public let version: Int
    /// Optional reason attached to the update.
    public let reason: String?
}

/// Supported primary AI providers for strict BYOK mode.
public enum AIPrimaryProvider: String, Codable, CaseIterable, Identifiable {
    case anthropic
    case openai
    case google

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic:
            return "Anthropic"
        case .openai:
            return "OpenAI"
        case .google:
            return "Google"
        }
    }

    public var onboardingLogoAssetName: String {
        switch self {
        case .anthropic:
            return "ProviderAnthropicLogo"
        case .openai:
            return "ProviderOpenAILogo"
        case .google:
            return "ProviderGoogleLogo"
        }
    }

    public var apiKeySetupURL: URL? {
        switch self {
        case .anthropic:
            return URL(string: "https://docs.trysidebar.ai/manual/api-keys#anthropic")
        case .openai:
            return URL(string: "https://docs.trysidebar.ai/manual/api-keys#openai")
        case .google:
            return URL(string: "https://docs.trysidebar.ai/manual/api-keys#google")
        }
    }
}

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
    /// Notification delivery preferences and schedule settings.
    public let notificationPreferences: NotificationPreferencesSettings
    /// The assistant identity value.
    public let assistantIdentity: AssistantIdentitySettings?
    /// Metadata about assistant identity updates.
    public let assistantIdentityMeta: AgentFieldMeta?
    /// The assistant soul value.
    public let assistantSoul: AssistantSoulSettings?
    /// Metadata about assistant soul updates.
    public let assistantSoulMeta: AgentFieldMeta?
    /// Primary AI provider selected for assistant and title generation.
    public let aiPrimaryProvider: String?
    /// Whether the selected primary provider currently has a saved key.
    public let aiPrimaryProviderHasKey: Bool
    /// Last 4 characters of the selected primary provider key.
    public let aiPrimaryProviderKeyLast4: String?
    /// The enabled skills value.
    public let enabledSkills: [String]
    /// Installed Store skills.
    public let installedStoreSkills: [String]

    private enum CodingKeys: String, CodingKey {
        case userId
        case communicationStyle
        case workingRelationship
        case name
        case jobTitle
        case employer
        case dateOfBirth
        case gender
        case pronouns
        case location
        case profileImageUrl
        case notificationPreferences
        case assistantIdentity
        case assistantIdentityMeta
        case assistantSoul
        case assistantSoulMeta
        case aiPrimaryProvider
        case aiPrimaryProviderHasKey
        case aiPrimaryProviderKeyLast4
        case enabledSkills
        case installedStoreSkills
    }

    public init(
        userId: String,
        communicationStyle: String?,
        workingRelationship: String?,
        name: String?,
        jobTitle: String?,
        employer: String?,
        dateOfBirth: String?,
        gender: String?,
        pronouns: String?,
        location: String?,
        profileImageUrl: String?,
        notificationPreferences: NotificationPreferencesSettings = .defaults,
        assistantIdentity: AssistantIdentitySettings? = nil,
        assistantIdentityMeta: AgentFieldMeta? = nil,
        assistantSoul: AssistantSoulSettings? = nil,
        assistantSoulMeta: AgentFieldMeta? = nil,
        aiPrimaryProvider: String? = nil,
        aiPrimaryProviderHasKey: Bool = false,
        aiPrimaryProviderKeyLast4: String? = nil,
        enabledSkills: [String],
        installedStoreSkills: [String] = []
    ) {
        self.userId = userId
        self.communicationStyle = communicationStyle
        self.workingRelationship = workingRelationship
        self.name = name
        self.jobTitle = jobTitle
        self.employer = employer
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.pronouns = pronouns
        self.location = location
        self.profileImageUrl = profileImageUrl
        self.notificationPreferences = notificationPreferences
        self.assistantIdentity = assistantIdentity
        self.assistantIdentityMeta = assistantIdentityMeta
        self.assistantSoul = assistantSoul
        self.assistantSoulMeta = assistantSoulMeta
        self.aiPrimaryProvider = aiPrimaryProvider
        self.aiPrimaryProviderHasKey = aiPrimaryProviderHasKey
        self.aiPrimaryProviderKeyLast4 = aiPrimaryProviderKeyLast4
        self.enabledSkills = enabledSkills
        self.installedStoreSkills = installedStoreSkills
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        communicationStyle = try container.decodeIfPresent(String.self, forKey: .communicationStyle)
        workingRelationship = try container.decodeIfPresent(String.self, forKey: .workingRelationship)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        jobTitle = try container.decodeIfPresent(String.self, forKey: .jobTitle)
        employer = try container.decodeIfPresent(String.self, forKey: .employer)
        dateOfBirth = try container.decodeIfPresent(String.self, forKey: .dateOfBirth)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        pronouns = try container.decodeIfPresent(String.self, forKey: .pronouns)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        profileImageUrl = try container.decodeIfPresent(String.self, forKey: .profileImageUrl)
        notificationPreferences = try container.decodeIfPresent(
            NotificationPreferencesSettings.self,
            forKey: .notificationPreferences
        ) ?? .defaults
        assistantIdentity = try container.decodeIfPresent(
            AssistantIdentitySettings.self,
            forKey: .assistantIdentity
        )
        assistantIdentityMeta = try container.decodeIfPresent(
            AgentFieldMeta.self,
            forKey: .assistantIdentityMeta
        )
        assistantSoul = try container.decodeIfPresent(
            AssistantSoulSettings.self,
            forKey: .assistantSoul
        )
        assistantSoulMeta = try container.decodeIfPresent(
            AgentFieldMeta.self,
            forKey: .assistantSoulMeta
        )
        aiPrimaryProvider = try container.decodeIfPresent(String.self, forKey: .aiPrimaryProvider)
        aiPrimaryProviderHasKey = try container.decodeIfPresent(
            Bool.self,
            forKey: .aiPrimaryProviderHasKey
        ) ?? false
        aiPrimaryProviderKeyLast4 = try container.decodeIfPresent(
            String.self,
            forKey: .aiPrimaryProviderKeyLast4
        )
        enabledSkills = try container.decodeIfPresent([String].self, forKey: .enabledSkills) ?? []
        installedStoreSkills = try container.decodeIfPresent(
            [String].self,
            forKey: .installedStoreSkills
        ) ?? []
    }
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
    /// Notification preference updates.
    public let notificationPreferences: NotificationPreferencesUpdate?
    /// The assistant identity value.
    public let assistantIdentity: AssistantIdentitySettings?
    /// Optional strict-BYOK primary provider update.
    public let aiPrimaryProvider: String?
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
        notificationPreferences: NotificationPreferencesUpdate? = nil,
        assistantIdentity: AssistantIdentitySettings? = nil,
        aiPrimaryProvider: String? = nil,
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
        self.notificationPreferences = notificationPreferences
        self.assistantIdentity = assistantIdentity
        self.aiPrimaryProvider = aiPrimaryProvider
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
        case notificationPreferences = "notification_preferences"
        case assistantIdentity = "assistant_identity"
        case aiPrimaryProvider = "ai_primary_provider"
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
        try container.encodeIfPresent(notificationPreferences, forKey: .notificationPreferences)
        try container.encodeIfPresent(assistantIdentity, forKey: .assistantIdentity)
        try container.encodeIfPresent(aiPrimaryProvider, forKey: .aiPrimaryProvider)
        try container.encodeIfPresent(enabledSkills, forKey: .enabledSkills)
    }
}

/// Provider-key status payload for strict BYOK settings.
public struct ProviderKeyStatusResponse: Codable {
    public let provider: String?
    public let hasKey: Bool
    public let keyLast4: String?
}

/// Request payload for creating/updating a provider key.
public struct ProviderKeyUpdate: Encodable {
    public let provider: String
    public let apiKey: String

    public init(provider: String, apiKey: String) {
        self.provider = provider
        self.apiKey = apiKey
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case apiKey = "api_key"
    }
}

/// Consumer source for provider-key disconnect operations.
public enum ProviderKeyDisconnectSource: String, Codable {
    case skill
    case aiProvider = "ai_provider"
}

/// Request payload for provider-key consumer disconnect.
public struct ProviderKeyDisconnectRequest: Encodable {
    public let provider: String
    public let source: ProviderKeyDisconnectSource
    public let skillId: String?

    public init(
        provider: String,
        source: ProviderKeyDisconnectSource,
        skillId: String? = nil
    ) {
        self.provider = provider
        self.source = source
        self.skillId = skillId
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case source
        case skillId = "skill_id"
    }
}

/// Actions performed by provider-key disconnect.
public struct ProviderKeyDisconnectActions: Codable {
    public let disabledSkillIds: [String]
    public let detachedAIProvider: Bool
    public let deletedProviderKey: Bool

    private enum CodingKeys: String, CodingKey {
        case disabledSkillIds
        case detachedAIProvider = "detachedAiProvider"
        case deletedProviderKey
    }
}

/// Remaining provider consumers after disconnect.
public struct ProviderKeyDisconnectRemainingConsumers: Codable {
    public let aiProvider: Bool
    public let skillIds: [String]
}

/// Settings snapshot returned by provider-key disconnect.
public struct ProviderKeyDisconnectSettings: Codable {
    public let enabledSkills: [String]
    public let installedStoreSkills: [String]
    public let aiPrimaryProvider: String?
}

/// Response payload for provider-key consumer disconnect.
public struct ProviderKeyDisconnectResponse: Codable {
    public let provider: String
    public let source: ProviderKeyDisconnectSource
    public let actions: ProviderKeyDisconnectActions
    public let remainingConsumers: ProviderKeyDisconnectRemainingConsumers
    public let settings: ProviderKeyDisconnectSettings
}

/// Represents a shortcuts token response struct.
public struct ShortcutsTokenResponse: Codable {
    /// The token value.
    public let token: String
}
