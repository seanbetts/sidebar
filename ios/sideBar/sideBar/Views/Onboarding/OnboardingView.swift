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

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: DesignTokens.Animation.standard), value: viewModel.currentStep)
                .contentShape(Rectangle())
                .simultaneousGesture(backSwipeGesture)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topChrome
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomArea
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
        viewModel.currentStepHasBack
    }

    @ViewBuilder
    private var topChrome: some View {
        if showsBackButton {
            backButton
        } else {
            Color.clear
                .frame(height: DesignTokens.Size.touchTarget)
                .padding(.horizontal, DesignTokens.Spacing.lg)
        }
    }

    @ViewBuilder
    private var bottomArea: some View {
        switch viewModel.currentStep {
        case .welcome:
            OnboardingBottomArea(
                totalSteps: viewModel.totalSteps,
                currentStep: viewModel.currentStepIndex
            ) {
                OnboardingActionArea {
                    Button(action: { viewModel.advance() }, label: {
                        Text("Get Started")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: 310)
                            .padding(.vertical, DesignTokens.Spacing.md)
                    })
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                } secondary: {
                    Button("Already have an account? Sign In", action: {
                        viewModel.routeToSignIn = true
                    })
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        case .createAccount:
            OnboardingBottomArea(
                totalSteps: viewModel.totalSteps,
                currentStep: viewModel.currentStepIndex
            ) {
                OnboardingActionArea(reservesSecondarySpace: true) {
                    Button(action: {
                        Task { await viewModel.createAccount() }
                    }, label: {
                        Group {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(DesignTokens.Colors.background)
                            } else {
                                Text("Continue")
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: 310)
                        .padding(.vertical, DesignTokens.Spacing.md)
                    })
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(!viewModel.isCreateAccountValid || viewModel.isLoading)
                    .opacity(viewModel.isCreateAccountValid ? 1.0 : 0.4)
                } secondary: {
                    Text(" ")
                        .font(.subheadline)
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
        case .verifyEmail:
            OnboardingBottomArea(
                totalSteps: viewModel.totalSteps,
                currentStep: viewModel.currentStepIndex
            ) {
                EmptyView()
            }
        case .profile:
            OnboardingBottomArea(
                totalSteps: viewModel.totalSteps,
                currentStep: viewModel.currentStepIndex
            ) {
                OnboardingActionArea {
                    Button(action: {
                        Task { await viewModel.saveProfile() }
                    }, label: {
                        Text("Continue")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: 310)
                            .padding(.vertical, DesignTokens.Spacing.md)
                    })
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                } secondary: {
                    Button("Skip for now", action: {
                        viewModel.skipProfile()
                    })
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        case .chooseProvider:
            OnboardingBottomArea(
                totalSteps: viewModel.totalSteps,
                currentStep: viewModel.currentStepIndex
            ) {
                OnboardingActionArea {
                    Button(action: { viewModel.advance() }, label: {
                        Text("Continue")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: 310)
                            .padding(.vertical, DesignTokens.Spacing.md)
                    })
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(viewModel.selectedProvider == nil)
                    .opacity(viewModel.selectedProvider == nil ? 0.4 : 1.0)
                } secondary: {
                    Button("Skip for now", action: {
                        Task { await viewModel.skipProviderSetup() }
                    })
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        case .addApiKey:
            OnboardingBottomArea(
                totalSteps: viewModel.totalSteps,
                currentStep: viewModel.currentStepIndex
            ) {
                OnboardingActionArea {
                    Button(action: {
                        Task { await viewModel.validateAndSaveApiKey() }
                    }, label: {
                        Group {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(DesignTokens.Colors.background)
                            } else {
                                Text("Verify & Continue")
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: 310)
                        .padding(.vertical, DesignTokens.Spacing.md)
                    })
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(viewModel.trimmedApiKey.isEmpty || viewModel.isLoading)
                    .opacity(viewModel.trimmedApiKey.isEmpty ? 0.4 : 1.0)
                } secondary: {
                    Button("Skip for now", action: {
                        Task { await viewModel.skipProviderSetup() }
                    })
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        case .transition:
            OnboardingBottomArea(
                totalSteps: viewModel.totalSteps,
                currentStep: viewModel.currentStepIndex
            ) {
                OnboardingActionArea(reservesSecondarySpace: true) {
                    Button(action: {
                        Task {
                            await viewModel.completeOnboarding()
                            dismiss()
                        }
                    }, label: {
                        Text("Meet sideBar")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: 310)
                            .padding(.vertical, DesignTokens.Spacing.md)
                    })
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                } secondary: {
                    Text(" ")
                        .font(.subheadline)
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard viewModel.currentStepHasBack,
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
