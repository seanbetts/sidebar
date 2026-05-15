import Foundation
import sideBarShared

/// Actionable Apple permission kinds exposed in signed-in settings recovery.
public enum OnboardingPermissionRecoveryKind: String, Identifiable, Equatable {
    case location
    case notifications

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .location:
            return "Enable location"
        case .notifications:
            return "Enable notifications"
        }
    }

    var message: String {
        switch self {
        case .location:
            return "Weather and local context need your permission."
        case .notifications:
            return "Task reminders and assistant follow-up need your permission."
        }
    }

    var appIcon: AppIcon {
        switch self {
        case .location:
            return AppIcon.Onboarding.locationPermission
        case .notifications:
            return AppIcon.Onboarding.notificationsPermission
        }
    }
}

/// A single permission recovery item rendered in the signed-in settings pane.
public struct OnboardingPermissionRecoveryItem: Identifiable, Equatable {
    public let kind: OnboardingPermissionRecoveryKind
    public let permissionState: OnboardingPermissionState

    public var id: String { kind.id }

    public var title: String { kind.title }
    public var message: String { kind.message }
    public var appIcon: AppIcon { kind.appIcon }
    public var actionTitle: String { permissionState == .denied ? "Open Settings" : "Enable" }
    public var opensSystemSettings: Bool { permissionState == .denied }
}

@MainActor
extension SettingsViewModel {
    public var permissionRecoveryItems: [OnboardingPermissionRecoveryItem] {
        guard let onboardingState else {
            return []
        }

        var items: [OnboardingPermissionRecoveryItem] = []
        if let locationItem = Self.permissionRecoveryItem(
            kind: .location,
            state: onboardingState.permissions.location
        ) {
            items.append(locationItem)
        }
        if let notificationsItem = Self.permissionRecoveryItem(
            kind: .notifications,
            state: onboardingState.permissions.notifications
        ) {
            items.append(notificationsItem)
        }
        return items
    }

    public func requestPermissionRecovery(
        for kind: OnboardingPermissionRecoveryKind
    ) async {
        let resolvedState: OnboardingPermissionState
        switch kind {
        case .location:
            resolvedState = await locationPermissionRequester.requestPermission()
            await persistPermissionRecoveryState(location: resolvedState)
        case .notifications:
            resolvedState = await notificationPermissionRequester.requestPermission()
            await persistPermissionRecoveryState(notifications: resolvedState)
        }
    }

    public func refreshPermissionRecoveryStates() async {
        guard let onboardingState else {
            return
        }

        let locationState = locationPermissionRequester.currentState
        let notificationsState = await notificationPermissionRequester.refreshCurrentState()

        guard locationState != onboardingState.permissions.location
                || notificationsState != onboardingState.permissions.notifications else {
            return
        }

        await persistPermissionRecoveryState(
            location: locationState,
            notifications: notificationsState
        )
    }

    private static func permissionRecoveryItem(
        kind: OnboardingPermissionRecoveryKind,
        state: OnboardingPermissionState?
    ) -> OnboardingPermissionRecoveryItem? {
        guard let state, state != .granted else {
            return nil
        }
        return OnboardingPermissionRecoveryItem(
            kind: kind,
            permissionState: state
        )
    }

    private func persistPermissionRecoveryState(
        location: OnboardingPermissionState? = nil,
        notifications: OnboardingPermissionState? = nil
    ) async {
        guard location != nil || notifications != nil else {
            return
        }

        if let onboardingAPI {
            do {
                let state = try await onboardingAPI.updateOnboarding(
                    OnboardingUpdate(
                        permissions: OnboardingPermissionsUpdate(
                            location: location,
                            notifications: notifications
                        )
                    )
                )
                setOnboardingState(state)
                return
            } catch {
                // Ignore transient onboarding sync failures and keep the last known state.
            }
        }

        guard let onboardingState else {
            return
        }

        setOnboardingState(OnboardingState(
            status: onboardingState.status,
            providerReady: onboardingState.providerReady,
            currentOnboardingStep: onboardingState.currentOnboardingStep,
            isOnboardingComplete: onboardingState.isOnboardingComplete,
            intent: onboardingState.intent,
            milestones: onboardingState.milestones,
            permissions: OnboardingPermissions(
                location: location ?? onboardingState.permissions.location,
                notifications: notifications ?? onboardingState.permissions.notifications
            ),
            lastPromptedAt: onboardingState.lastPromptedAt
        ))
    }
}
