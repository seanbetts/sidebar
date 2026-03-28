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
    case transition
}

@MainActor
/// Observable state and actions for the Phase 1 onboarding wizard.
public final class OnboardingViewModel: ObservableObject {
    @Published public var currentStep: OnboardingStep = .welcome
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var routeToSignIn = false

    @Published public var email = ""
    @Published public var password = ""
    @Published public var displayName = ""
    @Published public var selectedProvider: AIPrimaryProvider?
    @Published public var apiKey = ""

    public let isTestingOnboarding: Bool

    private let authSession: AuthSession
    private let onboardingAPI: OnboardingProviding
    private let settingsAPI: SettingsProviding
    private let userDefaults: UserDefaults
    private static let stepsWithBack: Set<OnboardingStep> = [
        .createAccount,
        .profile,
        .chooseProvider,
        .addApiKey
    ]
    private static let isoFormatter = ISO8601DateFormatter()
    private static let onboardingStatusKey = AppStorageKeys.onboardingStatus

    public init(
        authSession: AuthSession,
        onboardingAPI: OnboardingProviding,
        settingsAPI: SettingsProviding,
        isTestingOnboarding: Bool = ProcessInfo.processInfo.arguments.contains("-resetOnboarding"),
        userDefaults: UserDefaults = .standard
    ) {
        self.authSession = authSession
        self.onboardingAPI = onboardingAPI
        self.settingsAPI = settingsAPI
        self.isTestingOnboarding = isTestingOnboarding
        self.userDefaults = userDefaults
    }

    public var currentStepHasBack: Bool {
        Self.stepsWithBack.contains(currentStep)
    }

    public var totalSteps: Int {
        OnboardingStep.allCases.count
    }

    public var currentStepIndex: Int {
        currentStep.rawValue
    }

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
        switch selectedProvider {
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/keys")
        case .openai:
            return URL(string: "https://platform.openai.com/api-keys")
        case .google:
            return URL(string: "https://aistudio.google.com/apikey")
        case nil:
            return nil
        }
    }

    public var addApiKeySubtitle: String {
        let providerName = selectedProvider?.displayName ?? "your AI provider"
        return "Paste your \(providerName) API key so I can start helping you."
    }

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

    public func advance() {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    public func goBack() {
        guard currentStepHasBack,
              let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = previous
    }

    public func createAccount() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            if isTestingOnboarding {
                advance()
                return
            }

            try await authSession.signUp(email: email, password: password)
            advance()
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
                advance()
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
            advance()
        } catch {
            errorMessage = "Invalid verification code. Please try again."
        }
    }

    /// Resends the verification code by retrying the sign-up request.
    public func resendVerificationCode() async throws {
        try await authSession.signUp(email: email, password: password)
    }

    public func saveProfile() async {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedName.isEmpty {
            _ = try? await settingsAPI.updateSettings(SettingsUpdate(name: trimmedName))
            _ = try? await onboardingAPI.updateOnboarding(
                OnboardingUpdate(
                    milestones: OnboardingMilestonesUpdate(
                        profileBasicsSet: Self.isoFormatter.string(from: Date())
                    )
                )
            )
        }

        advance()
    }

    public func skipProfile() {
        advance()
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
                advance()
                return
            }

            _ = try await settingsAPI.updateSettings(
                SettingsUpdate(aiPrimaryProvider: provider.rawValue)
            )
            _ = try await settingsAPI.upsertProviderKey(provider: provider.rawValue, apiKey: key)
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
            advance()
        } catch {
            errorMessage = "Could not validate your API key. Please check it and try again."
        }
    }

    public func skipProviderSetup() async {
        if isTestingOnboarding {
            persistOnboardingStatus(.dismissed)
            currentStep = .transition
            return
        }

        let state = try? await onboardingAPI.updateOnboarding(OnboardingUpdate(status: .dismissed))
        if let status = state?.status {
            persistOnboardingStatus(status)
        } else {
            persistOnboardingStatus(.dismissed)
        }
        currentStep = .transition
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
}

/// Determines when onboarding should be shown and which presentation style to use.
public enum OnboardingPresentation {
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

#if canImport(UIKit)
    public static func style(for idiom: UIUserInterfaceIdiom) -> Style {
        idiom == .phone ? .fullScreenCover : .sheet
    }
#endif
}
