import Foundation

/// Backend calibration status values.
public enum OnboardingCalibrationStatus: String, Codable, Equatable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case awaitingNameAcceptance = "awaiting_name_acceptance"
    case completed
}

/// Ordered calibration prompt identifiers returned by the backend.
public enum OnboardingCalibrationPrompt: String, Codable, Equatable {
    case primaryGoal = "primary_goal"
    case workingRelationship = "working_relationship"
    case tonePreferences = "tone_preferences"
}

/// Stored calibration answers returned by the onboarding endpoint.
public struct OnboardingCalibrationAnswers: Codable, Equatable {
    public let primaryGoal: String?
    public let workingRelationship: String?
    public let tonePreferences: String?

    public static let `default` = OnboardingCalibrationAnswers(
        primaryGoal: nil,
        workingRelationship: nil,
        tonePreferences: nil
    )

    public init(
        primaryGoal: String?,
        workingRelationship: String?,
        tonePreferences: String?
    ) {
        self.primaryGoal = primaryGoal
        self.workingRelationship = workingRelationship
        self.tonePreferences = tonePreferences
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        primaryGoal = container.decodeStringIfPresent(
            snakeCase: "primary_goal",
            camelCase: "primaryGoal"
        )
        workingRelationship = container.decodeStringIfPresent(
            snakeCase: "working_relationship",
            camelCase: "workingRelationship"
        )
        tonePreferences = container.decodeStringIfPresent(
            snakeCase: "tone_preferences",
            camelCase: "tonePreferences"
        )
    }
}

/// Calibration progress returned by the onboarding endpoint.
public struct OnboardingCalibrationState: Codable, Equatable {
    public let status: OnboardingCalibrationStatus
    public let currentPrompt: OnboardingCalibrationPrompt
    public let answers: OnboardingCalibrationAnswers
    public let proposedName: String?
    public let completedAt: String?

    public static let `default` = OnboardingCalibrationState(
        status: .notStarted,
        currentPrompt: .primaryGoal,
        answers: .default,
        proposedName: nil,
        completedAt: nil
    )

    public init(
        status: OnboardingCalibrationStatus,
        currentPrompt: OnboardingCalibrationPrompt,
        answers: OnboardingCalibrationAnswers,
        proposedName: String?,
        completedAt: String?
    ) {
        self.status = status
        self.currentPrompt = currentPrompt
        self.answers = answers
        self.proposedName = proposedName
        self.completedAt = completedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        status = try container.decode(
            OnboardingCalibrationStatus.self,
            snakeCase: "status",
            camelCase: "status"
        )
        currentPrompt = try container.decode(
            OnboardingCalibrationPrompt.self,
            snakeCase: "current_prompt",
            camelCase: "currentPrompt"
        )
        answers = try container.decode(
            OnboardingCalibrationAnswers.self,
            snakeCase: "answers",
            camelCase: "answers"
        )
        proposedName = container.decodeStringIfPresent(
            snakeCase: "proposed_name",
            camelCase: "proposedName"
        )
        completedAt = container.decodeStringIfPresent(
            snakeCase: "completed_at",
            camelCase: "completedAt"
        )
    }
}

/// Client-side representation of a calibration answer before request encoding.
public enum OnboardingCalibrationAnswer: Equatable {
    case singleChoice(String)
    case multipleChoice([String])
    case freeform(String)

    var requestValue: String {
        switch self {
        case let .singleChoice(value), let .freeform(value):
            return value
        case let .multipleChoice(values):
            return values.joined(separator: ",")
        }
    }
}

/// Structured calibration action response returned by the onboarding API.
public struct OnboardingCalibrationActionResponse: Codable, Equatable {
    public let state: OnboardingState
    public let calibration: OnboardingCalibrationState
    public let assistantIdentity: AssistantIdentitySettings?
    public let assistantSoul: AssistantSoulSettings?
    public let confirmationText: String?

    public init(
        state: OnboardingState,
        calibration: OnboardingCalibrationState,
        assistantIdentity: AssistantIdentitySettings?,
        assistantSoul: AssistantSoulSettings?,
        confirmationText: String?
    ) {
        self.state = state
        self.calibration = calibration
        self.assistantIdentity = assistantIdentity
        self.assistantSoul = assistantSoul
        self.confirmationText = confirmationText
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        state = try container.decode(
            OnboardingState.self,
            snakeCase: "state",
            camelCase: "state"
        )
        calibration = try container.decode(
            OnboardingCalibrationState.self,
            snakeCase: "calibration",
            camelCase: "calibration"
        )
        assistantIdentity = try container.decodeIfPresent(
            AssistantIdentitySettings.self,
            snakeCase: "assistant_identity",
            camelCase: "assistantIdentity"
        )
        assistantSoul = try container.decodeIfPresent(
            AssistantSoulSettings.self,
            snakeCase: "assistant_soul",
            camelCase: "assistantSoul"
        )
        confirmationText = container.decodeStringIfPresent(
            snakeCase: "confirmation_text",
            camelCase: "confirmationText"
        )
    }
}
