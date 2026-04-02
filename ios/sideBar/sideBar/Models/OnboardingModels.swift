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

/// Derived onboarding step returned by the backend.
public enum OnboardingCurrentStep: String, Codable, Equatable {
    case phase1Wizard = "phase1_wizard"
    case providerRecovery = "provider_recovery"
    case permissionRecovery = "permission_recovery"
    case soulCalibration = "soul_calibration"
    case featureDiscovery = "feature_discovery"
    case completed
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

    public init(
        providerConnected: String?,
        firstOutcomeCompleted: String?,
        profileBasicsSet: String?,
        communicationStyleSet: String?,
        secondaryTourSeen: String?
    ) {
        self.providerConnected = providerConnected
        self.firstOutcomeCompleted = firstOutcomeCompleted
        self.profileBasicsSet = profileBasicsSet
        self.communicationStyleSet = communicationStyleSet
        self.secondaryTourSeen = secondaryTourSeen
    }

    enum CodingKeys: String, CodingKey {
        case providerConnected = "provider_connected"
        case firstOutcomeCompleted = "first_outcome_completed"
        case profileBasicsSet = "profile_basics_set"
        case communicationStyleSet = "communication_style_set"
        case secondaryTourSeen = "secondary_tour_seen"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        providerConnected = container.decodeStringIfPresent(
            snakeCase: "provider_connected",
            camelCase: "providerConnected"
        )
        firstOutcomeCompleted = container.decodeStringIfPresent(
            snakeCase: "first_outcome_completed",
            camelCase: "firstOutcomeCompleted"
        )
        profileBasicsSet = container.decodeStringIfPresent(
            snakeCase: "profile_basics_set",
            camelCase: "profileBasicsSet"
        )
        communicationStyleSet = container.decodeStringIfPresent(
            snakeCase: "communication_style_set",
            camelCase: "communicationStyleSet"
        )
        secondaryTourSeen = container.decodeStringIfPresent(
            snakeCase: "secondary_tour_seen",
            camelCase: "secondaryTourSeen"
        )
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
    public let currentOnboardingStep: OnboardingCurrentStep
    public let isOnboardingComplete: Bool
    public let intent: OnboardingIntent?
    public let calibration: OnboardingCalibrationState
    public let milestones: OnboardingMilestones
    public let permissions: OnboardingPermissions
    public let lastPromptedAt: String?

    public init(
        status: OnboardingStatus,
        providerReady: Bool,
        currentOnboardingStep: OnboardingCurrentStep,
        isOnboardingComplete: Bool,
        intent: OnboardingIntent?,
        calibration: OnboardingCalibrationState = .default,
        milestones: OnboardingMilestones,
        permissions: OnboardingPermissions,
        lastPromptedAt: String?
    ) {
        self.status = status
        self.providerReady = providerReady
        self.currentOnboardingStep = currentOnboardingStep
        self.isOnboardingComplete = isOnboardingComplete
        self.intent = intent
        self.calibration = calibration
        self.milestones = milestones
        self.permissions = permissions
        self.lastPromptedAt = lastPromptedAt
    }

    enum CodingKeys: String, CodingKey {
        case status
        case providerReady = "provider_ready"
        case currentOnboardingStep = "current_onboarding_step"
        case isOnboardingComplete = "is_onboarding_complete"
        case intent
        case calibration
        case milestones
        case permissions
        case lastPromptedAt = "last_prompted_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        status = try container.decode(
            OnboardingStatus.self,
            snakeCase: "status",
            camelCase: "status"
        )
        providerReady = try container.decode(
            Bool.self,
            snakeCase: "provider_ready",
            camelCase: "providerReady"
        )
        currentOnboardingStep = try container.decode(
            OnboardingCurrentStep.self,
            snakeCase: "current_onboarding_step",
            camelCase: "currentOnboardingStep"
        )
        isOnboardingComplete = try container.decode(
            Bool.self,
            snakeCase: "is_onboarding_complete",
            camelCase: "isOnboardingComplete"
        )
        intent = try container.decodeIfPresent(
            OnboardingIntent.self,
            snakeCase: "intent",
            camelCase: "intent"
        )
        calibration = try container.decodeIfPresent(
            OnboardingCalibrationState.self,
            snakeCase: "calibration",
            camelCase: "calibration"
        ) ?? .default
        milestones = try container.decode(
            OnboardingMilestones.self,
            snakeCase: "milestones",
            camelCase: "milestones"
        )
        permissions = try container.decode(
            OnboardingPermissions.self,
            snakeCase: "permissions",
            camelCase: "permissions"
        )
        lastPromptedAt = container.decodeStringIfPresent(
            snakeCase: "last_prompted_at",
            camelCase: "lastPromptedAt"
        )
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

struct FlexibleCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer where Key == FlexibleCodingKey {
    func decode<T: Decodable>(
        _ type: T.Type,
        snakeCase: String,
        camelCase: String
    ) throws -> T {
        if let key = FlexibleCodingKey(stringValue: snakeCase),
           contains(key) {
            return try decode(T.self, forKey: key)
        }
        let key = FlexibleCodingKey(stringValue: camelCase)!
        return try decode(T.self, forKey: key)
    }

    func decodeIfPresent<T: Decodable>(
        _ type: T.Type,
        snakeCase: String,
        camelCase: String
    ) throws -> T? {
        if let key = FlexibleCodingKey(stringValue: snakeCase),
           contains(key) {
            return try decodeIfPresent(T.self, forKey: key)
        }
        let key = FlexibleCodingKey(stringValue: camelCase)!
        return try decodeIfPresent(T.self, forKey: key)
    }

    func decodeStringIfPresent(
        snakeCase: String,
        camelCase: String
    ) -> String? {
        if let key = FlexibleCodingKey(stringValue: snakeCase),
           contains(key) {
            return try? decodeIfPresent(String.self, forKey: key)
        }
        let key = FlexibleCodingKey(stringValue: camelCase)!
        return try? decodeIfPresent(String.self, forKey: key)
    }
}
