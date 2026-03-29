import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Local wizard step used to drive onboarding UI.
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

extension OnboardingViewModel {
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
