import Foundation

public struct OnboardingSyncPayload: Codable, Equatable {
    public let status: OnboardingStatus?
    public let providerConnected: String?
    public let profileBasicsSet: String?
    public let locationPermission: OnboardingPermissionState?
    public let notificationsPermission: OnboardingPermissionState?

    public init(
        status: OnboardingStatus? = nil,
        providerConnected: String? = nil,
        profileBasicsSet: String? = nil,
        locationPermission: OnboardingPermissionState? = nil,
        notificationsPermission: OnboardingPermissionState? = nil
    ) {
        self.status = status
        self.providerConnected = providerConnected
        self.profileBasicsSet = profileBasicsSet
        self.locationPermission = locationPermission
        self.notificationsPermission = notificationsPermission
    }

    public var entityId: String {
        "onboarding"
    }

    public var update: OnboardingUpdate {
        OnboardingUpdate(
            status: status,
            milestones: OnboardingMilestonesUpdate(
                providerConnected: providerConnected,
                profileBasicsSet: profileBasicsSet
            ),
            permissions: OnboardingPermissionsUpdate(
                location: locationPermission,
                notifications: notificationsPermission
            )
        )
    }
}

public extension OnboardingState {
    func applying(_ payload: OnboardingSyncPayload) -> OnboardingState {
        OnboardingState(
            status: payload.status ?? status,
            providerReady: payload.providerConnected == nil ? providerReady : true,
            currentOnboardingStep: currentOnboardingStep,
            isOnboardingComplete: isOnboardingComplete,
            intent: intent,
            calibration: calibration,
            milestones: OnboardingMilestones(
                providerConnected: payload.providerConnected ?? milestones.providerConnected,
                firstOutcomeCompleted: milestones.firstOutcomeCompleted,
                profileBasicsSet: payload.profileBasicsSet ?? milestones.profileBasicsSet,
                communicationStyleSet: milestones.communicationStyleSet,
                secondaryTourSeen: milestones.secondaryTourSeen
            ),
            permissions: OnboardingPermissions(
                location: payload.locationPermission ?? permissions.location,
                notifications: payload.notificationsPermission ?? permissions.notifications
            ),
            lastPromptedAt: lastPromptedAt
        )
    }

    func withOnboardingStatus(_ newStatus: OnboardingStatus) -> OnboardingState {
        applying(OnboardingSyncPayload(status: newStatus))
    }
}
