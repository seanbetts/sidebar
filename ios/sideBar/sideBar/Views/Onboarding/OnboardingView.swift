import SwiftUI

/// Container for the Phase 1 onboarding wizard.
struct OnboardingView: View {
    @StateObject private var viewModel: OnboardingViewModel
    @Environment(\.dismiss) private var dismiss
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

    var body: some View {
        ZStack {
            DesignTokens.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if showsBackButton {
                    backButton
                } else {
                    Color.clear
                        .frame(height: DesignTokens.Size.touchTarget)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                }

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeInOut(duration: DesignTokens.Animation.standard), value: viewModel.currentStep)
                    .contentShape(Rectangle())
                    .simultaneousGesture(backSwipeGesture)

                OnboardingProgressDots(
                    totalSteps: viewModel.totalSteps,
                    currentStep: viewModel.currentStepIndex
                )
                .padding(.bottom, DesignTokens.Spacing.lg)
            }
        }
        .interactiveDismissDisabled()
        .onChange(of: viewModel.routeToSignIn) { _, shouldRouteToSignIn in
            guard shouldRouteToSignIn else { return }
            onRouteToSignIn()
            dismiss()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            WelcomeStepView(viewModel: viewModel)
        case .createAccount:
            CreateAccountStepView(viewModel: viewModel)
        case .verifyEmail:
            VerifyEmailStepView(viewModel: viewModel)
        case .profile:
            ProfileStepView(viewModel: viewModel)
        case .chooseProvider:
            ChooseProviderStepView(viewModel: viewModel)
        case .addApiKey:
            AddApiKeyStepView(viewModel: viewModel)
        case .transition:
            TransitionStepView(viewModel: viewModel, dismiss: dismiss)
        }
    }

    private var showsBackButton: Bool {
        viewModel.currentStepHasBack && viewModel.currentStep != .createAccount
    }

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard viewModel.currentStep == .createAccount,
                      value.translation.width > 90,
                      abs(value.translation.height) < 60 else {
                    return
                }
                viewModel.goBack()
            }
    }

    private var backButton: some View {
        HStack {
            Button(action: { viewModel.goBack() }, label: {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                    Text("Back")
                        .font(.body)
                }
                .foregroundStyle(.primary)
            })
            .frame(height: DesignTokens.Size.touchTarget)
            .padding(.horizontal, DesignTokens.Spacing.lg)

            Spacer()
        }
    }
}
