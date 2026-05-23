import Foundation

/// Skill tier from catalog metadata.
public enum SkillTier: String, Codable {
    case required
    case standard
    case store
}

/// Settings section from catalog metadata.
public enum SkillSettingsSection: String, Codable {
    case app
    case agent
    case system
}

/// Credential requirement metadata for a skill.
public struct SkillCredentialRequirement: Codable, Equatable {
    public let provider: String
    public let keyKind: String
    public let required: Bool
    public let source: String?
    public let mode: String?

    public init(
        provider: String,
        keyKind: String = "api_key",
        required: Bool,
        source: String? = nil,
        mode: String? = nil
    ) {
        self.provider = provider
        self.keyKind = keyKind
        self.required = required
        self.source = source
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case keyKind
        case required
        case source
        case mode
        case legacyKeyKind = "key_kind"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        keyKind = try container.decodeIfPresent(String.self, forKey: .keyKind)
            ?? container.decodeIfPresent(String.self, forKey: .legacyKeyKind)
            ?? "api_key"
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        source = try container.decodeIfPresent(String.self, forKey: .source)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(keyKind, forKey: .keyKind)
        try container.encode(required, forKey: .required)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(mode, forKey: .mode)
    }
}

/// Represents a skill item struct.
public struct SkillItem: Codable, Identifiable {
    /// The id value.
    public let id: String
    /// Legacy IDs accepted by backend.
    public let legacyIds: [String]
    /// The name value.
    public let name: String
    /// The description value.
    public let description: String
    /// The category value.
    public let category: String
    /// Settings section for grouping skills in settings.
    public let settingsSection: SkillSettingsSection
    /// Symbol/icon key for UI rendering.
    public let iconKey: String
    /// Skill tier for skills/settings grouping.
    public let tier: SkillTier
    /// Provider dependency metadata.
    public let providerDependency: String
    /// Credential requirements for install/execution.
    public let credentialRequirements: [SkillCredentialRequirement]
    /// Whether users are allowed to toggle this skill.
    public let userToggleable: Bool
    /// Whether this skill is enabled by default.
    public let defaultEnabled: Bool
    /// Whether this skill can be installed from Store.
    public let installable: Bool
    /// Catalog status (active, beta, hidden, deprecated).
    public let status: String
    /// Optional longer user-facing description for detail modal.
    public let longDescription: String?
    /// Optional non-technical explanation of how the skill works.
    public let howItWorks: String?
    /// Optional user-facing requirements beyond provider-key metadata.
    public let requirements: [String]
    /// Optional semantic version string for the skill.
    public let version: String?
    /// Optional ISO-8601 date for last metadata update.
    public let updatedAt: String?
    /// Future-facing aggregate install count.
    public let installCount: Int?
    /// Future-facing aggregate upvotes.
    public let upvotes: Int?
    /// Future-facing aggregate downvotes.
    public let downvotes: Int?
    /// Future-facing current user vote (`up`, `down`, `none`).
    public let currentUserVote: String?

    public init(
        id: String,
        legacyIds: [String] = [],
        name: String,
        description: String,
        category: String,
        settingsSection: SkillSettingsSection = .system,
        iconKey: String? = nil,
        tier: SkillTier = .standard,
        providerDependency: String = "none",
        credentialRequirements: [SkillCredentialRequirement] = [],
        userToggleable: Bool = true,
        defaultEnabled: Bool = false,
        installable: Bool = false,
        status: String = "active",
        longDescription: String? = nil,
        howItWorks: String? = nil,
        requirements: [String] = [],
        version: String? = nil,
        updatedAt: String? = nil,
        installCount: Int? = nil,
        upvotes: Int? = nil,
        downvotes: Int? = nil,
        currentUserVote: String? = nil
    ) {
        self.id = id
        self.legacyIds = legacyIds
        self.name = name
        self.description = description
        self.category = category
        self.settingsSection = settingsSection
        self.iconKey = iconKey ?? id
        self.tier = tier
        self.providerDependency = providerDependency
        self.credentialRequirements = credentialRequirements
        self.userToggleable = userToggleable
        self.defaultEnabled = defaultEnabled
        self.installable = installable
        self.status = status
        self.longDescription = longDescription
        self.howItWorks = howItWorks
        self.requirements = requirements
        self.version = version
        self.updatedAt = updatedAt
        self.installCount = installCount
        self.upvotes = upvotes
        self.downvotes = downvotes
        self.currentUserVote = currentUserVote
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case legacyIds
        case name
        case description
        case category
        case settingsSection
        case iconKey
        case tier
        case providerDependency
        case credentialRequirements
        case userToggleable
        case defaultEnabled
        case installable
        case status
        case longDescription
        case howItWorks
        case requirements
        case version
        case updatedAt
        case installCount
        case upvotes
        case downvotes
        case currentUserVote
        case legacyLegacyIds = "legacy_ids"
        case legacySettingsSection = "settings_section"
        case legacyIconKey = "icon_key"
        case legacyProviderDependency = "provider_dependency"
        case legacyCredentialRequirements = "credential_requirements"
        case legacyUserToggleable = "user_toggleable"
        case legacyDefaultEnabled = "default_enabled"
        case legacyLongDescription = "long_description"
        case legacyHowItWorks = "how_it_works"
        case legacyUpdatedAt = "updated_at"
        case legacyInstallCount = "install_count"
        case legacyCurrentUserVote = "current_user_vote"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        legacyIds = try Self.decodePreferred(
            [String].self,
            from: container,
            primary: .legacyIds,
            legacy: .legacyLegacyIds,
            default: []
        )
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        category = try container.decode(String.self, forKey: .category)
        settingsSection = try Self.decodePreferred(
            SkillSettingsSection.self,
            from: container,
            primary: .settingsSection,
            legacy: .legacySettingsSection,
            default: .system
        )
        iconKey = try Self.decodePreferred(
            String.self,
            from: container,
            primary: .iconKey,
            legacy: .legacyIconKey,
            default: id
        )
        tier = try container.decodeIfPresent(SkillTier.self, forKey: .tier) ?? .standard
        providerDependency = try Self.decodePreferred(
            String.self,
            from: container,
            primary: .providerDependency,
            legacy: .legacyProviderDependency,
            default: "none"
        )
        credentialRequirements = try Self.decodePreferred(
            [SkillCredentialRequirement].self,
            from: container,
            primary: .credentialRequirements,
            legacy: .legacyCredentialRequirements,
            default: []
        )
        userToggleable = try Self.decodePreferred(
            Bool.self,
            from: container,
            primary: .userToggleable,
            legacy: .legacyUserToggleable,
            default: true
        )
        defaultEnabled = try Self.decodePreferred(
            Bool.self,
            from: container,
            primary: .defaultEnabled,
            legacy: .legacyDefaultEnabled,
            default: false
        )
        installable = try container.decodeIfPresent(Bool.self, forKey: .installable) ?? false
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "active"
        longDescription = try container.decodeIfPresent(String.self, forKey: .longDescription)
            ?? container.decodeIfPresent(String.self, forKey: .legacyLongDescription)
        howItWorks = try container.decodeIfPresent(String.self, forKey: .howItWorks)
            ?? container.decodeIfPresent(String.self, forKey: .legacyHowItWorks)
        requirements = try container.decodeIfPresent([String].self, forKey: .requirements) ?? []
        version = try container.decodeIfPresent(String.self, forKey: .version)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .legacyUpdatedAt)
        installCount = try container.decodeIfPresent(Int.self, forKey: .installCount)
            ?? container.decodeIfPresent(Int.self, forKey: .legacyInstallCount)
        upvotes = try container.decodeIfPresent(Int.self, forKey: .upvotes)
        downvotes = try container.decodeIfPresent(Int.self, forKey: .downvotes)
        currentUserVote = try container.decodeIfPresent(String.self, forKey: .currentUserVote)
            ?? container.decodeIfPresent(String.self, forKey: .legacyCurrentUserVote)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(legacyIds, forKey: .legacyIds)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(category, forKey: .category)
        try container.encode(settingsSection, forKey: .settingsSection)
        try container.encode(iconKey, forKey: .iconKey)
        try container.encode(tier, forKey: .tier)
        try container.encode(providerDependency, forKey: .providerDependency)
        try container.encode(credentialRequirements, forKey: .credentialRequirements)
        try container.encode(userToggleable, forKey: .userToggleable)
        try container.encode(defaultEnabled, forKey: .defaultEnabled)
        try container.encode(installable, forKey: .installable)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(longDescription, forKey: .longDescription)
        try container.encodeIfPresent(howItWorks, forKey: .howItWorks)
        try container.encode(requirements, forKey: .requirements)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(installCount, forKey: .installCount)
        try container.encodeIfPresent(upvotes, forKey: .upvotes)
        try container.encodeIfPresent(downvotes, forKey: .downvotes)
        try container.encodeIfPresent(currentUserVote, forKey: .currentUserVote)
    }

    private static func decodePreferred<T: Decodable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        primary: CodingKeys,
        legacy: CodingKeys,
        default defaultValue: @autoclosure () -> T
    ) throws -> T {
        if let modern = try container.decodeIfPresent(type, forKey: primary) {
            return modern
        }
        if let legacyValue = try container.decodeIfPresent(type, forKey: legacy) {
            return legacyValue
        }
        return defaultValue()
    }
}

/// Represents a skills response struct.
public struct SkillsResponse: Codable {
    /// Catalog version for cache-busting client behavior.
    public let catalogVersion: Int
    /// The skills value.
    public let skills: [SkillItem]

    private enum CodingKeys: String, CodingKey {
        case catalogVersion
        case skills
        case legacyCatalogVersion = "catalog_version"
    }

    public init(catalogVersion: Int = 1, skills: [SkillItem]) {
        self.catalogVersion = catalogVersion
        self.skills = skills
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        catalogVersion = try container.decodeIfPresent(Int.self, forKey: .catalogVersion)
            ?? container.decodeIfPresent(Int.self, forKey: .legacyCatalogVersion)
            ?? 1
        skills = try container.decodeIfPresent([SkillItem].self, forKey: .skills) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(catalogVersion, forKey: .catalogVersion)
        try container.encode(skills, forKey: .skills)
    }
}

/// Install-time provider key input for Store skill installs.
public struct StoreSkillProviderKeyInput: Encodable, Equatable {
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

/// Request payload for Store skill install.
public struct StoreSkillInstallRequest: Encodable {
    public let skillId: String
    public let providerKeys: [StoreSkillProviderKeyInput]

    public init(skillId: String, providerKeys: [StoreSkillProviderKeyInput] = []) {
        self.skillId = skillId
        self.providerKeys = providerKeys
    }

    private enum CodingKeys: String, CodingKey {
        case skillId = "skill_id"
        case providerKeys = "provider_keys"
    }
}

/// Request payload for Store skill uninstall.
public struct StoreSkillUninstallRequest: Encodable {
    public let skillId: String

    public init(skillId: String) {
        self.skillId = skillId
    }

    private enum CodingKeys: String, CodingKey {
        case skillId = "skill_id"
    }
}

/// Response payload for Store skill install.
public struct StoreSkillInstallResponse: Codable, Equatable {
    public let skillId: String
    public let installed: Bool
    public let enabled: Bool
    public let enabledSkills: [String]
    public let installedStoreSkills: [String]

    private enum CodingKeys: String, CodingKey {
        case skillId
        case installed
        case enabled
        case enabledSkills
        case installedStoreSkills
        case legacySkillId = "skill_id"
        case legacyEnabledSkills = "enabled_skills"
        case legacyInstalledStoreSkills = "installed_store_skills"
    }

    public init(
        skillId: String,
        installed: Bool,
        enabled: Bool,
        enabledSkills: [String],
        installedStoreSkills: [String]
    ) {
        self.skillId = skillId
        self.installed = installed
        self.enabled = enabled
        self.enabledSkills = enabledSkills
        self.installedStoreSkills = installedStoreSkills
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skillId = try container.decodeIfPresent(String.self, forKey: .skillId)
            ?? container.decodeIfPresent(String.self, forKey: .legacySkillId)
            ?? ""
        installed = try container.decodeIfPresent(Bool.self, forKey: .installed) ?? false
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        enabledSkills = try container.decodeIfPresent([String].self, forKey: .enabledSkills)
            ?? container.decodeIfPresent([String].self, forKey: .legacyEnabledSkills)
            ?? []
        installedStoreSkills = try container.decodeIfPresent([String].self, forKey: .installedStoreSkills)
            ?? container.decodeIfPresent([String].self, forKey: .legacyInstalledStoreSkills)
            ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(skillId, forKey: .skillId)
        try container.encode(installed, forKey: .installed)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(enabledSkills, forKey: .enabledSkills)
        try container.encode(installedStoreSkills, forKey: .installedStoreSkills)
    }
}
