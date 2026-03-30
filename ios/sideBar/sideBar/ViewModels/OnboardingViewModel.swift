import Foundation
import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
/// Observable state and actions for the Phase 1 onboarding wizard.
public final class OnboardingViewModel: ObservableObject {
    @Published public var currentStep: OnboardingStep = .welcome
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var routeToSignIn = false
    @Published public private(set) var navigationDirection: OnboardingNavigationDirection = .forward

    @Published public var email = ""
    @Published public var password = ""
    @Published public var displayName = ""
    @Published public var selectedProvider: AIPrimaryProvider?
    @Published public var apiKey = ""
    @Published public private(set) var locationPermissionState: OnboardingPermissionState = .notAsked
    @Published public private(set) var notificationsPermissionState: OnboardingPermissionState = .notAsked
    @Published public private(set) var isRefreshingNotificationsPermissionState = false

    public let isTestingOnboarding: Bool

    private let authSession: AuthSession
    private let onboardingAPI: OnboardingProviding
    private let settingsAPI: SettingsProviding
    private let locationPermissionRequester: any LocationPermissionRequesting
    private let notificationsPermissionRequester: any NotificationPermissionRequesting
    private let userDefaults: UserDefaults
    private var skippedProviderSetup = false
    private var resolvedPermissionSteps = Set<OnboardingStep>()
    private static let stepsWithBack: Set<OnboardingStep> = [
        .createAccount,
        .verifyEmail,
        .profile,
        .chooseProvider,
        .addApiKey,
        .locationPermission,
        .notificationsPermission,
        .finalStep
    ]
    private static let isoFormatter = ISO8601DateFormatter()
    private static let onboardingStatusKey = AppStorageKeys.onboardingStatus

    public init(
        authSession: AuthSession,
        onboardingAPI: OnboardingProviding,
        settingsAPI: SettingsProviding,
        locationPermissionRequester: (any LocationPermissionRequesting)? = nil,
        notificationsPermissionRequester: (any NotificationPermissionRequesting)? = nil,
        isTestingOnboarding: Bool? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.authSession = authSession
        self.onboardingAPI = onboardingAPI
        self.settingsAPI = settingsAPI
        self.locationPermissionRequester = locationPermissionRequester ?? LocationPermissionRequester()
        self.notificationsPermissionRequester = notificationsPermissionRequester ?? NotificationPermissionRequester()
        self.isTestingOnboarding = isTestingOnboarding ?? OnboardingPresentation.isTestingOnboardingEnabled()
        self.userDefaults = userDefaults
    }

    public var currentStepHasBack: Bool { Self.stepsWithBack.contains(currentStep) }
    public var totalSteps: Int { OnboardingStep.allCases.count }
    public var currentStepIndex: Int { currentStep.rawValue }
    public var isLocationPermissionResolved: Bool { resolvedPermissionSteps.contains(.locationPermission) }
    public var isNotificationsPermissionResolved: Bool { resolvedPermissionSteps.contains(.notificationsPermission) }

    var transitionVariant: OnboardingTransitionVariant {
        skippedProviderSetup ? .providerSetupSkipped : .providerConnected
    }

    var transitionTitle: String {
        transitionVariant == .providerConnected ? "You're All Set" : "You're Ready To Explore"
    }

    var transitionSubtitle: String {
        transitionVariant == .providerConnected
            ? "I'm connected and ready to go.\nLet me show you around."
            : "You can start using sideBar now, even without connecting an AI provider yet."
    }

    var transitionHighlights: [String] {
        switch transitionVariant {
        case .providerConnected:
            return []
        case .providerSetupSkipped:
            return [
                "You can still capture notes, tasks, files, and save websites to read later.",
                "Chat and other assistant-powered features stay unavailable until you add an API key.",
                "You can connect your AI brain later in Settings whenever you're ready."
            ]
        }
    }

    public func advance() {
        guard canAdvance(from: currentStep) else { return }
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        navigate(to: next, direction: .forward)
    }

    public func advance(from expectedStep: OnboardingStep) {
        guard currentStep == expectedStep else { return }
        advance()
    }

    public func goBack() {
        guard currentStepHasBack else { return }
        guard let previous = previousStep(for: currentStep) else { return }
        navigate(to: previous, direction: .backward)
    }

    public func selectProvider(_ provider: AIPrimaryProvider) {
        selectedProvider = provider
        skippedProviderSetup = false
        errorMessage = nil
    }

    public func createAccount() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            if isTestingOnboarding {
                advance(from: .createAccount)
                return
            }

            try await authSession.signUp(email: email, password: password)
            advance(from: .createAccount)
        } catch {
            errorMessage = ErrorMapping.message(for: error)
        }
    }

    public func verifyOTP(code: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            if isTestingOnboarding {
                persistOnboardingStatus(.inProgress)
                advance(from: .verifyEmail)
                return
            }

            try await authSession.verifyOTP(email: email, code: code)
            let state = try? await onboardingAPI.updateOnboarding(
                OnboardingUpdate(status: .inProgress)
            )
            if let status = state?.status {
                persistOnboardingStatus(status)
            } else {
                persistOnboardingStatus(.inProgress)
            }
            advance(from: .verifyEmail)
        } catch {
            errorMessage = "Invalid verification code. Please try again."
        }
    }

    /// Resends the verification code by retrying the sign-up request.
    public func resendVerificationCode() async throws {
        try await authSession.signUp(email: email, password: password)
    }

    public func saveProfile() async {
        guard currentStep == .profile else { return }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileBasicsTimestamp = Self.isoFormatter.string(from: Date())

        advance(from: .profile)

        if !trimmedName.isEmpty {
            let settingsAPI = settingsAPI
            let onboardingAPI = onboardingAPI
            Task {
                _ = try? await settingsAPI.updateSettings(SettingsUpdate(name: trimmedName))
                _ = try? await onboardingAPI.updateOnboarding(
                    OnboardingUpdate(
                        milestones: OnboardingMilestonesUpdate(
                            profileBasicsSet: profileBasicsTimestamp
                        )
                    )
                )
            }
        }
    }

    public func skipProfile() {
        advance(from: .profile)
    }

    public func skipLocationPermission() async {
        await resolveLocationPermission(.notAsked)
    }

    public func enableLocationPermission() async {
        guard !(isLocationPermissionResolved && locationPermissionState == .granted) else {
            advance()
            return
        }

        let state = await locationPermissionRequester.requestPermission()
        await resolveLocationPermission(state)
    }

    public func skipNotificationsPermission() async {
        await resolveNotificationsPermission(.notAsked)
    }

    public func enableNotificationsPermission() async {
        guard !(isNotificationsPermissionResolved && notificationsPermissionState == .granted) else {
            advance()
            return
        }

        let state = await notificationsPermissionRequester.requestPermission()
        await resolveNotificationsPermission(state)
    }

    public func validateAndSaveApiKey() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        guard let provider = selectedProvider else {
            errorMessage = "Please go back and select a provider."
            return
        }

        let key = trimmedApiKey
        guard !key.isEmpty else {
            errorMessage = "Please enter your API key."
            return
        }

        do {
            if isTestingOnboarding {
                persistOnboardingStatus(.inProgress)
                advance(from: .addApiKey)
                return
            }

            _ = try await settingsAPI.updateSettings(
                SettingsUpdate(aiPrimaryProvider: provider.rawValue)
            )
            _ = try await settingsAPI.upsertProviderKey(provider: provider.rawValue, apiKey: key)
            skippedProviderSetup = false
            let state = try? await onboardingAPI.updateOnboarding(
                OnboardingUpdate(
                    milestones: OnboardingMilestonesUpdate(
                        providerConnected: Self.isoFormatter.string(from: Date())
                    )
                )
            )
            if let status = state?.status {
                persistOnboardingStatus(status)
            } else {
                persistOnboardingStatus(.inProgress)
            }
            advance(from: .addApiKey)
        } catch {
            errorMessage = "Could not validate your API key. Please check it and try again."
        }
    }

    public func refreshPermissionStateForCurrentStep() async {
        switch currentStep {
        case .locationPermission:
            refreshLocationPermissionState(locationPermissionRequester.currentState)
        case .notificationsPermission:
            refreshNotificationsPermissionState(notificationsPermissionRequester.currentState)
            isRefreshingNotificationsPermissionState = true
            let state = await notificationsPermissionRequester.refreshCurrentState()
            isRefreshingNotificationsPermissionState = false
            refreshNotificationsPermissionState(state)
        default:
            isRefreshingNotificationsPermissionState = false
            return
        }
    }

    public func skipProviderSetup() async {
        skippedProviderSetup = true

        if isTestingOnboarding {
            persistOnboardingStatus(.inProgress)
            navigate(to: .locationPermission, direction: .forward)
            return
        }

        let state = try? await onboardingAPI.updateOnboarding(OnboardingUpdate(status: .inProgress))
        if let status = state?.status {
            persistOnboardingStatus(status)
        } else {
            persistOnboardingStatus(.inProgress)
        }
        navigate(to: .locationPermission, direction: .forward)
    }

    public func completeOnboarding() async {
        if isTestingOnboarding {
            persistOnboardingStatus(.completed)
            return
        }

        let state = try? await onboardingAPI.updateOnboarding(OnboardingUpdate(status: .completed))
        if let status = state?.status {
            persistOnboardingStatus(status)
        } else {
            persistOnboardingStatus(.completed)
        }
    }

    private func persistOnboardingStatus(_ status: OnboardingStatus) {
        userDefaults.set(status.rawValue, forKey: Self.onboardingStatusKey)
    }

    private func resolveLocationPermission(_ state: OnboardingPermissionState) async {
        syncLocationPermissionState(state)

        if !isTestingOnboarding {
            _ = try? await onboardingAPI.updateOnboarding(
                OnboardingUpdate(
                    permissions: OnboardingPermissionsUpdate(location: state)
                )
            )
        }

        advance(from: .locationPermission)
    }

    private func resolveNotificationsPermission(_ state: OnboardingPermissionState) async {
        syncNotificationsPermissionState(state)

        if !isTestingOnboarding {
            _ = try? await onboardingAPI.updateOnboarding(
                OnboardingUpdate(
                    permissions: OnboardingPermissionsUpdate(notifications: state)
                )
            )
        }

        advance(from: .notificationsPermission)
    }

    private func syncLocationPermissionState(_ state: OnboardingPermissionState) {
        locationPermissionState = state
        resolvedPermissionSteps.insert(.locationPermission)
    }

    private func syncNotificationsPermissionState(_ state: OnboardingPermissionState) {
        notificationsPermissionState = state
        resolvedPermissionSteps.insert(.notificationsPermission)
    }

    private func refreshLocationPermissionState(_ state: OnboardingPermissionState) {
        refreshPermissionState(
            state,
            for: .locationPermission
        ) { [weak self] refreshedState in
            self?.locationPermissionState = refreshedState
        }
    }

    private func refreshNotificationsPermissionState(_ state: OnboardingPermissionState) {
        refreshPermissionState(
            state,
            for: .notificationsPermission
        ) { [weak self] refreshedState in
            self?.notificationsPermissionState = refreshedState
        }
    }

    private func refreshPermissionState(
        _ state: OnboardingPermissionState,
        for step: OnboardingStep,
        apply: (OnboardingPermissionState) -> Void
    ) {
        if state == .notAsked {
            if !resolvedPermissionSteps.contains(step) {
                apply(.notAsked)
            }
            return
        }

        apply(state)
        resolvedPermissionSteps.insert(step)
    }

    private func navigate(
        to step: OnboardingStep,
        direction: OnboardingNavigationDirection
    ) {
        navigationDirection = direction
        withAnimation(OnboardingMotion.animation(for: direction)) {
            currentStep = step
        }
        refreshPermissionStateIfNeeded(for: step)
    }

    private func refreshPermissionStateIfNeeded(for step: OnboardingStep) {
        switch step {
        case .locationPermission:
            isRefreshingNotificationsPermissionState = false
            refreshLocationPermissionState(locationPermissionRequester.currentState)
            Task { [weak self] in
                await self?.refreshPermissionStateForCurrentStep()
            }
        case .notificationsPermission:
            isRefreshingNotificationsPermissionState = true
            refreshNotificationsPermissionState(notificationsPermissionRequester.currentState)
            Task { [weak self] in
                await self?.refreshPermissionStateForCurrentStep()
            }
        default:
            isRefreshingNotificationsPermissionState = false
            return
        }
    }

    private func previousStep(for step: OnboardingStep) -> OnboardingStep? {
        switch step {
        case .locationPermission:
            return (skippedProviderSetup || selectedProvider == nil) ? .chooseProvider : .addApiKey
        case .addApiKey:
            return .chooseProvider
        default:
            return OnboardingStep(rawValue: step.rawValue - 1)
        }
    }

    private func canAdvance(from step: OnboardingStep) -> Bool {
        switch step {
        case .chooseProvider:
            return selectedProvider != nil
        case .locationPermission:
            return isLocationPermissionResolved
        case .notificationsPermission:
            return isNotificationsPermissionResolved
        default:
            return true
        }
    }
}
