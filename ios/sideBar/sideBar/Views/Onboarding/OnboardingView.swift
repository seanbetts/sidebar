import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Container for the Phase 1 onboarding wizard.
struct OnboardingView: View {
    @StateObject private var viewModel: OnboardingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSoftwareKeyboardVisible = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var bottomAreaHeight: CGFloat = 0
    #if os(macOS)
    @State private var allowsTerminationDismiss = false
    #endif
    let onRouteToSignIn: () -> Void

    init(
        authSession: AuthSession,
        onboardingAPI: OnboardingProviding,
        settingsAPI: SettingsProviding,
        onRouteToSignIn: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(
            wrappedValue: OnboardingViewModel(
                authSession: authSession,
                onboardingAPI: onboardingAPI,
                settingsAPI: settingsAPI
            )
        )
        self.onRouteToSignIn = onRouteToSignIn
    }

    init(
        viewModel: OnboardingViewModel,
        onRouteToSignIn: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onRouteToSignIn = onRouteToSignIn
    }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background
                .ignoresSafeArea()

            OnboardingStepTransitionContainer(
                step: viewModel.currentStep,
                direction: viewModel.navigationDirection
            ) {
                stepContent
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(backSwipeGesture)
        }
        .overlay(alignment: .topLeading) {
            if showsBackButton {
                backButton
                    .padding(.top, DesignTokens.Spacing.xs)
            }
        }
        .overlay(alignment: .bottom) {
            if OnboardingChromeLayoutPolicy.bottomAreaPlacement == .overlay {
                bottomArea
                    .background(DesignTokens.Colors.background)
                    .onboardingBottomAreaHeightReader()
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .interactiveDismissDisabled(shouldDisableInteractiveDismiss)
        .onOnboardingBottomAreaHeightChange { height in
            bottomAreaHeight = height
        }
        .task(id: viewModel.currentStep) {
            await viewModel.refreshPermissionStateForCurrentStep()
        }
#if canImport(UIKit)
        .modifier(OnboardingKeyboardSafeAreaModifier(isEnabled: OnboardingChromeLayoutPolicy.rootIgnoresKeyboardSafeArea))
#endif
        .onChange(of: viewModel.routeToSignIn) { _, shouldRouteToSignIn in
            guard shouldRouteToSignIn else { return }
            onRouteToSignIn()
            dismiss()
        }
#if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            updateKeyboardPresentation(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            updateKeyboardPresentation(from: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isSoftwareKeyboardVisible = false
            keyboardHeight = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            isSoftwareKeyboardVisible = false
            keyboardHeight = 0
        }
#endif
#if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .macAppTerminationRequested)) { _ in
            allowsTerminationDismiss = true
        }
#endif
    }

    @ViewBuilder
    private var stepContent: some View {
        switch Self.contentKind(for: viewModel.currentStep) {
        case .welcome:
            WelcomeStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        case .createAccount:
            CreateAccountStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        case .verifyEmail:
            VerifyEmailStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        case .profile:
            ProfileStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        case .chooseProvider:
            ChooseProviderStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        case .addApiKey:
            AddApiKeyStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        case .locationPermission:
            LocationPermissionStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        case .notificationsPermission:
            NotificationsPermissionStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        case .finalStep:
            FinalStepView(
                viewModel: viewModel,
                layoutMode: layoutMode,
                bottomContentInset: effectiveBottomContentInset
            )
        }
    }

    static func contentKind(for step: OnboardingStep) -> OnboardingStepContentKind {
        switch step {
        case .welcome:
            return .welcome
        case .createAccount:
            return .createAccount
        case .verifyEmail:
            return .verifyEmail
        case .profile:
            return .profile
        case .chooseProvider:
            return .chooseProvider
        case .addApiKey:
            return .addApiKey
        case .locationPermission:
            return .locationPermission
        case .notificationsPermission:
            return .notificationsPermission
        case .finalStep:
            return .finalStep
        }
    }

    private var effectiveBottomContentInset: CGFloat {
        OnboardingChromeLayoutPolicy.contentBottomInset(
            for: bottomAreaHeight,
            keyboardHeight: keyboardHeight
        )
    }

    private var layoutMode: OnboardingLayoutMode {
        OnboardingChromeLayoutPolicy.layoutMode(isSoftwareKeyboardVisible: isSoftwareKeyboardVisible)
    }

    private var showsBackButton: Bool {
        viewModel.currentStepHasBack
    }

    private var bottomArea: some View {
        OnboardingBottomAreaView(
            viewModel: viewModel,
            layoutMode: layoutMode,
            dismiss: dismiss
        )
    }

    private var shouldDisableInteractiveDismiss: Bool {
        #if os(macOS)
        !allowsTerminationDismiss
        #else
        true
        #endif
    }

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard OnboardingBackSwipePolicy.shouldNavigateBack(
                    hasBackButton: viewModel.currentStepHasBack,
                    startLocation: value.startLocation,
                    translation: value.translation
                ) else {
                    return
                }
                viewModel.goBack()
            }
    }

    private var backButton: some View {
        Button(action: { viewModel.goBack() }, label: {
            HStack(spacing: DesignTokens.Spacing.xxs) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                Text("Back")
                    .font(.body)
            }
            .foregroundStyle(.primary)
        })
        .buttonStyle(.plain)
        .frame(height: DesignTokens.Size.touchTarget)
        .padding(.horizontal, DesignTokens.Spacing.lg)
    }

#if canImport(UIKit)
    private func updateKeyboardPresentation(from notification: Notification) {
        let height = keyboardHeight(from: notification)
        keyboardHeight = height
        isSoftwareKeyboardVisible = height > 0
    }

    private func keyboardHeight(from notification: Notification) -> CGFloat {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return 0
        }
        let screenMaxY = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen
            .bounds
            .maxY ?? frame.maxY
        return OnboardingKeyboardMetrics.softwareKeyboardHeight(
            from: frame,
            screenMaxY: screenMaxY
        )
    }
#endif
}

enum OnboardingStepContentKind: Equatable {
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

enum OnboardingBackSwipePolicy {
    private static let minimumHorizontalTranslation: CGFloat = 90
    private static let maximumVerticalDrift: CGFloat = 60
    private static let maximumLeadingEdgeStartX: CGFloat = DesignTokens.Size.touchTarget

    static func shouldNavigateBack(
        hasBackButton: Bool,
        startLocation: CGPoint,
        translation: CGSize
    ) -> Bool {
        guard hasBackButton else { return false }
        guard startLocation.x <= maximumLeadingEdgeStartX else { return false }
        guard translation.width > minimumHorizontalTranslation else { return false }
        guard abs(translation.height) < maximumVerticalDrift else { return false }
        return true
    }
}

#if canImport(UIKit)
private struct OnboardingKeyboardSafeAreaModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.ignoresSafeArea(.keyboard, edges: .bottom)
        } else {
            content
        }
    }
}
#endif
