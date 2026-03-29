import Foundation
import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Local wizard step used to drive Phase 1 onboarding UI.
public enum OnboardingStep: Int, CaseIterable {
    case welcome
    case createAccount
    case verifyEmail
    case profile
    case chooseProvider
    case addApiKey
    case locationPermission
    case notificationsPermission
    case finalStep
}

enum OnboardingTransitionVariant: Equatable {
    case providerConnected
    case providerSetupSkipped
}

/// Indicates whether the wizard is moving forward or backward between steps.
public enum OnboardingNavigationDirection: Equatable {
    case forward
    case backward
}

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
        isTestingOnboarding: Bool = ProcessInfo.processInfo.arguments.contains("-resetOnboarding"),
        userDefaults: UserDefaults = .standard
    ) {
        self.authSession = authSession
        self.onboardingAPI = onboardingAPI
        self.settingsAPI = settingsAPI
        self.locationPermissionRequester = locationPermissionRequester ?? LocationPermissionRequester()
        self.notificationsPermissionRequester = notificationsPermissionRequester ?? NotificationPermissionRequester()
        self.isTestingOnboarding = isTestingOnboarding
        self.userDefaults = userDefaults
    }

    public var currentStepHasBack: Bool { Self.stepsWithBack.contains(currentStep) }
    public var totalSteps: Int { OnboardingStep.allCases.count }
    public var currentStepIndex: Int { currentStep.rawValue }

    public var isEmailValid: Bool {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    /// Scores password strength from 0 to 4 based on increasingly strict criteria.
    public var passwordStrength: Int {
        let candidate = password
        guard candidate.count >= 8 else { return 0 }

        var score = 1
        if candidate.rangeOfCharacter(from: .uppercaseLetters) != nil &&
            candidate.rangeOfCharacter(from: .lowercaseLetters) != nil {
            score += 1
        }
        if candidate.rangeOfCharacter(from: .decimalDigits) != nil {
            score += 1
        }
        let specials = CharacterSet.alphanumerics.inverted
        if candidate.unicodeScalars.contains(where: { specials.contains($0) }) {
            score += 1
        }
        return score
    }

    public var isCreateAccountValid: Bool {
        isEmailValid && password.count >= 8
    }

    public var trimmedApiKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var providerHelpURL: URL? {
        selectedProvider?.apiKeySetupURL
    }

    public var addApiKeySubtitle: String {
        let providerName = selectedProvider?.displayName ?? "your AI provider"
        return "Paste your \(providerName) API key so I can start helping you."
    }

    public var isLocationPermissionResolved: Bool { resolvedPermissionSteps.contains(.locationPermission) }
    public var isNotificationsPermissionResolved: Bool { resolvedPermissionSteps.contains(.notificationsPermission) }

    public var apiKeyPlaceholder: String {
        switch selectedProvider {
        case .anthropic:
            return "sk-ant-..."
        case .openai:
            return "sk-..."
        case .google:
            return "AI..."
        case nil:
            return "Paste your API key"
        }
    }

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
        guard !isLocationPermissionResolved else {
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
        guard !isNotificationsPermissionResolved else {
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
        locationPermissionState = state
        resolvedPermissionSteps.insert(.locationPermission)

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
        notificationsPermissionState = state
        resolvedPermissionSteps.insert(.notificationsPermission)

        if !isTestingOnboarding {
            _ = try? await onboardingAPI.updateOnboarding(
                OnboardingUpdate(
                    permissions: OnboardingPermissionsUpdate(notifications: state)
                )
            )
        }

        advance(from: .notificationsPermission)
    }

    private func navigate(
        to step: OnboardingStep,
        direction: OnboardingNavigationDirection
    ) {
        navigationDirection = direction
        withAnimation(OnboardingMotion.animation(for: direction)) {
            currentStep = step
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

/// Determines when onboarding should be shown and which presentation style to use.
public enum OnboardingPresentation {
    /// Signed-out root content to show behind or instead of the onboarding flow.
    public enum SignedOutContent: Equatable {
        case login
        case onboardingBackdrop
    }

    /// Modal presentation style chosen for the current device family.
    public enum Style: Equatable {
        case fullScreenCover
        case sheet
    }

    public static func shouldPresent(
        authState: AuthState,
        onboardingStatus: OnboardingStatus,
        isTestingOnboarding: Bool
    ) -> Bool {
        if isTestingOnboarding {
            return true
        }
        return authState == .signedOut && onboardingStatus == .notStarted
    }

    public static func shouldAllowManualStart(authState: AuthState) -> Bool {
        authState == .signedOut
    }

    public static func signedOutContent(
        authState: AuthState,
        isOnboardingPresented: Bool
    ) -> SignedOutContent {
        guard authState == .signedOut else {
            return .login
        }
        return isOnboardingPresented ? .onboardingBackdrop : .login
    }

#if canImport(UIKit)
    public static func style(for idiom: UIUserInterfaceIdiom) -> Style {
        idiom == .phone ? .fullScreenCover : .sheet
    }
#endif
}
