import Foundation

/// Backend onboarding status values.
public enum OnboardingStatus: String, Codable, Equatable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case completed
    case dismissed
}

/// User intent captured during onboarding.
public enum OnboardingIntent: String, Codable, Equatable {
    case notes
    case tasks
    case websites
    case files
    case chat
}

/// Permission state for a single Apple permission.
public enum OnboardingPermissionState: String, Codable, Equatable {
    case notAsked = "not_asked"
    case granted
    case denied
}

/// Milestone timestamps from the backend onboarding state.
public struct OnboardingMilestones: Codable, Equatable {
    public let providerConnected: String?
    public let firstOutcomeCompleted: String?
    public let profileBasicsSet: String?
    public let communicationStyleSet: String?
    public let secondaryTourSeen: String?

    enum CodingKeys: String, CodingKey {
        case providerConnected = "provider_connected"
        case firstOutcomeCompleted = "first_outcome_completed"
        case profileBasicsSet = "profile_basics_set"
        case communicationStyleSet = "communication_style_set"
        case secondaryTourSeen = "secondary_tour_seen"
    }
}

/// Permission states returned by the onboarding endpoint.
public struct OnboardingPermissions: Codable, Equatable {
    public let location: OnboardingPermissionState
    public let notifications: OnboardingPermissionState
}

/// Full onboarding state returned by `GET /api/v1/onboarding`.
public struct OnboardingState: Codable, Equatable {
    public let status: OnboardingStatus
    public let providerReady: Bool
    public let intent: OnboardingIntent?
    public let milestones: OnboardingMilestones
    public let permissions: OnboardingPermissions
    public let lastPromptedAt: String?

    enum CodingKeys: String, CodingKey {
        case status
        case providerReady = "provider_ready"
        case intent
        case milestones
        case permissions
        case lastPromptedAt = "last_prompted_at"
    }
}

/// Partial update sent via `PATCH /api/v1/onboarding`.
public struct OnboardingUpdate: Encodable {
    public var status: OnboardingStatus?
    public var intent: OnboardingIntent?
    public var milestones: OnboardingMilestonesUpdate?
    public var permissions: OnboardingPermissionsUpdate?

    public init(
        status: OnboardingStatus? = nil,
        intent: OnboardingIntent? = nil,
        milestones: OnboardingMilestonesUpdate? = nil,
        permissions: OnboardingPermissionsUpdate? = nil
    ) {
        self.status = status
        self.intent = intent
        self.milestones = milestones
        self.permissions = permissions
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(intent, forKey: .intent)
        try container.encodeIfPresent(milestones, forKey: .milestones)
        try container.encodeIfPresent(permissions, forKey: .permissions)
    }

    enum CodingKeys: String, CodingKey {
        case status
        case intent
        case milestones
        case permissions
    }
}

/// Partial milestone update. Only non-nil fields are encoded.
public struct OnboardingMilestonesUpdate: Encodable {
    public var providerConnected: String?
    public var firstOutcomeCompleted: String?
    public var profileBasicsSet: String?
    public var communicationStyleSet: String?
    public var secondaryTourSeen: String?

    public init(
        providerConnected: String? = nil,
        firstOutcomeCompleted: String? = nil,
        profileBasicsSet: String? = nil,
        communicationStyleSet: String? = nil,
        secondaryTourSeen: String? = nil
    ) {
        self.providerConnected = providerConnected
        self.firstOutcomeCompleted = firstOutcomeCompleted
        self.profileBasicsSet = profileBasicsSet
        self.communicationStyleSet = communicationStyleSet
        self.secondaryTourSeen = secondaryTourSeen
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(providerConnected, forKey: .providerConnected)
        try container.encodeIfPresent(firstOutcomeCompleted, forKey: .firstOutcomeCompleted)
        try container.encodeIfPresent(profileBasicsSet, forKey: .profileBasicsSet)
        try container.encodeIfPresent(communicationStyleSet, forKey: .communicationStyleSet)
        try container.encodeIfPresent(secondaryTourSeen, forKey: .secondaryTourSeen)
    }

    enum CodingKeys: String, CodingKey {
        case providerConnected = "provider_connected"
        case firstOutcomeCompleted = "first_outcome_completed"
        case profileBasicsSet = "profile_basics_set"
        case communicationStyleSet = "communication_style_set"
        case secondaryTourSeen = "secondary_tour_seen"
    }
}

/// Partial permissions update. Only non-nil fields are encoded.
public struct OnboardingPermissionsUpdate: Encodable {
    public var location: OnboardingPermissionState?
    public var notifications: OnboardingPermissionState?

    public init(
        location: OnboardingPermissionState? = nil,
        notifications: OnboardingPermissionState? = nil
    ) {
        self.location = location
        self.notifications = notifications
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(notifications, forKey: .notifications)
    }

    enum CodingKeys: String, CodingKey {
        case location
        case notifications
    }
}
